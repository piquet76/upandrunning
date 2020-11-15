provider "aws" {
	region = "ap-northeast-2"
}

data "aws_ami" "latest-ubuntu" {
most_recent = true
owners = ["099720109477"] # Canonical

  filter {
      name   = "name"
      values = ["ubuntu/images/hvm-ssd/ubuntu-xenial-16.04-amd64-server-*"]
  }

  filter {
      name   = "virtualization-type"
      values = ["hvm"]
  }
}

resource "aws_launch_configuration" "example_lc" {
	image_id = data.aws_ami.latest-ubuntu.id
	instance_type = "t2.micro"
	
	user_data = <<-EOF
				#!/bin/bash
				echo "Hello world" > index.html
				nohup busybox httpd -f -p ${var.server_port} &
				EOF
				
	security_groups = [aws_security_group.example_sg.id]
	
	lifecycle {
		create_before_destroy = true
	}
}

resource "aws_autoscaling_group" "example_asg" {
	launch_configuration = aws_launch_configuration.example_lc.name
	vpc_zone_identifier =data.aws_subnet_ids.default.ids
	target_group_arns = [aws_lb_target_group.example_alb_tg.arn]
	health_check_type = "ELB"
	
	min_size =2
	max_size = 10
	
	tag {
		key = "Name"
		value = "tf-asg-example"
		propagate_at_launch = true
	}
}

data "aws_vpc" "default" {
	default = true
}

data "aws_subnet_ids" "default" {
	vpc_id = data.aws_vpc.default.id
}


resource "aws_security_group" "example_sg" {
	name = "terraform-example-sg"
	
	ingress {
		from_port = var.server_port
		to_port = var.server_port
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
}

resource "aws_lb" "example_lb" {
	name = "terraform-example-lb"
	load_balancer_type = "application"
	subnets = data.aws_subnet_ids.default.ids
	security_groups = [aws_security_group.example_alb_sg.id]
}

resource "aws_lb_listener" "http" {
	load_balancer_arn = aws_lb.example_lb.arn
	port = 80
	protocol = "HTTP"
	
	default_action {
		type = "fixed-response"
		
		fixed_response {
			content_type = "text/plain"
			message_body = "404: Page Not Found"
			status_code = 404
		}
	}
}

resource "aws_security_group" "example_alb_sg" {
	name = "terraform-example-alb-sg"
	ingress {
		from_port = 80
		to_port = 80
		protocol = "tcp"
		cidr_blocks = ["0.0.0.0/0"]
	}
	egress {
		from_port = 0
		to_port = 0
		protocol = "-1"
		cidr_blocks = ["0.0.0.0/0"]
	}
}

resource "aws_lb_target_group" "example_alb_tg" {
	name = "terraform-asg-example"
	port = var.server_port
	protocol = "HTTP"
	vpc_id = data.aws_vpc.default.id
	
	health_check {
		path = "/"
		protocol = "HTTP"
		matcher = "200"
		interval = 15
		timeout = 3
		healthy_threshold = 2
		unhealthy_threshold = 2
	}
}

resource "aws_lb_listener_rule" "example_lr" {
	listener_arn = aws_lb_listener.http.arn
	priority = 100
	
	condition {
		path_pattern {
			values = ["*"]
		}
	}
	action {
		type = "forward"
		target_group_arn = aws_lb_target_group.example_alb_tg.arn
	}
}



variable "server_port" {
	description = "The port for the server requests"
	type = number
}

output "alb_dns_name" {
	value = aws_lb.example_lb.dns_name
	description = "DNS of our LB"
}
