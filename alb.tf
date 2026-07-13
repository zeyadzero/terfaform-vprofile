resource "aws_lb" "lb_tomcat" {
  name               = "lb-tomcat"
  internal           = false # internet facing
  load_balancer_type = "application"
  security_groups    = [aws_security_group.lb.id]

  subnets = local.alb_subnet_ids

  tags = {
    Name = "lb-tomcat"
  }
}

resource "aws_lb_target_group" "vprofile" {
  name     = "vprofile"
  port     = 8080
  protocol = "HTTP"
  vpc_id   = data.aws_vpc.default.id

  target_type = "instance"

  health_check {
    path                = "/login"
    port                = "8080"
    protocol            = "HTTP"
    healthy_threshold   = 3
    unhealthy_threshold = 3
    interval            = 30
    timeout             = 5
  }

  # The app doesn't share sessions/CSRF tokens between tomcat1 and tomcat2,
  # so without stickiness a login POST can land on a different instance
  # than the GET that issued the CSRF token, causing 403 errors.
  stickiness {
    type            = "lb_cookie"
    cookie_duration = 3600
    enabled         = true
  }

  tags = {
    Name = "vprofile"
  }
}

resource "aws_lb_target_group_attachment" "tomcat1" {
  target_group_arn = aws_lb_target_group.vprofile.arn
  target_id        = aws_instance.tomcat1.id
  port             = 8080
}

resource "aws_lb_target_group_attachment" "tomcat2" {
  target_group_arn = aws_lb_target_group.vprofile.arn
  target_id        = aws_instance.tomcat2.id
  port             = 8080
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.lb_tomcat.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.vprofile.arn
  }
}
