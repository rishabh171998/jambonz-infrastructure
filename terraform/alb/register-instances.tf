# Register EC2 instances with target groups

resource "aws_lb_target_group_attachment" "api_server" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.api_server.arn
  target_id       = var.instance_ids[count.index]
  port            = 3000
}

resource "aws_lb_target_group_attachment" "webapp" {
  count            = length(var.instance_ids)
  target_group_arn = aws_lb_target_group.webapp.arn
  target_id       = var.instance_ids[count.index]
  port            = 3001
}

