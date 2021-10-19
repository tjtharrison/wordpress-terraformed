provider "aws" {
    version = "3.22.0"
    region = "eu-west-1"
    shared_credentials_file = "~/.aws/credentials"
}

## RDS
resource "aws_security_group" "wordpress_web" {
    name = "wordpress_web"
    description = "Wordpress Webserver"
    
    ingress {
        description = "SSH from safe subnet"
        from_port = var.ssh_port
        to_port = var.ssh_port
        protocol = "TCP"
        cidr_blocks = [var.safe_cidr]
    }

    ingress {
        description = "HTTP from safe subnet"
        from_port = var.app_http_port
        to_port = var.app_http_port
        protocol = "TCP"
        cidr_blocks = [var.safe_cidr]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "wordpress_web"
    }
}

resource "aws_db_instance" "wordpress_db" {
    allocated_storage = 10
    engine = "mysql"
    engine_version = "5.7"
    instance_class = "db.t3.micro"
    name = "wordpress_db"
    identifier = "wordpress-db"
    username = "admin"
    password = "password"
    parameter_group_name = "default.mysql5.7"
    vpc_security_group_ids = [ "${aws_security_group.wordpress_db.id}" ]
    skip_final_snapshot  = true
}

## Webserver
resource "aws_security_group" "wordpress_db" {
    name = "wordpress_db"
    description = "Wordpress Databases"
    
    ingress {
        description = "Mysql from Wordpress Instance"
        from_port = "3306"
        to_port = "3306"
        protocol = "TCP"
        security_groups = [ "${aws_security_group.wordpress_web.id}" ]
    }

    egress {
        from_port   = 0
        to_port     = 0
        protocol    = "-1"
        cidr_blocks = ["0.0.0.0/0"]
    }

    tags = {
        Name = "wordpress_db"
    }
}

resource "aws_instance" "wordpress_web" {
    ami = "ami-0aef57767f5404a3c"
    instance_type = var.instance_type
    vpc_security_group_ids = [ "${aws_security_group.wordpress_web.id}" ]
    tags = {
        Name = "wordpress_web"
    }

    ## Configure Server
    provisioner "remote-exec" {
        inline = [
            "sudo apt update",
            "sudo apt install python3 python3-pip -y",
            "echo Python installed!"
        ]

        connection {
            host        = self.public_ip
            type        = "ssh"
            user        = "ubuntu"
        }
    }

    provisioner "local-exec" {
        command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ubuntu -i '${self.public_ip},' ./ansible/install-docker.yaml"
    }

    provisioner "local-exec" {
        command = "sed -i 's/DB_PLACEHOLDER_SERVER/${aws_db_instance.wordpress_db.endpoint}/g' ./resources/docker-compose.yaml && sed -i 's/DB_PLACEHOLDER_USERNAME/${aws_db_instance.wordpress_db.username}/g'  ./resources/docker-compose.yaml && sed -i 's/DB_PLACEHOLDER_PASSWORD/${aws_db_instance.wordpress_db.password}/g' ./resources/docker-compose.yaml"
    }

    provisioner "local-exec" {
        command = "ANSIBLE_HOST_KEY_CHECKING=False ansible-playbook -u ubuntu -i '${self.public_ip},' ./ansible/deploy-wordpress.yaml"
    }

}
## Print Output
output "instance_public_ip" {
    description = "Public IP Address of the instance"
    value = aws_instance.wordpress_web.public_ip
}