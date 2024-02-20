
provider "aws" {
  region     = "eu-north-1"
  access_key = "AKIAZI2LIL7HUBKVT3YF"
  secret_key = "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"
}
#estructura de la red

resource "aws_vpc" "acme-vpc" {
   cidr_block = "10.0.0.0/16"
   tags = {
     Name = "acme_prueba"
   }
 }

resource "aws_internet_gateway" "gw" {
   vpc_id = aws_vpc.acme-vpc.id
}
resource "aws_subnet" "acme-subnet" {
  vpc_id                  = aws_vpc.acme-vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "eu-north-1a"  
}
resource "aws_subnet" "acme-subnet2" {
  vpc_id                  = aws_vpc.acme-vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "eu-north-1b"  
}

resource "aws_route_table" "acme-route" {
   vpc_id = aws_vpc.acme-vpc.id

   route {
     cidr_block = "0.0.0.0/0"
     gateway_id = aws_internet_gateway.gw.id
   }
 }

 resource "aws_route_table_association" "asociacion" {
  subnet_id      = aws_subnet.acme-subnet.id
  route_table_id = aws_route_table.acme-route.id
}

 resource "aws_eip" "lb" {
   
  instance      = aws_instance.application.id
  domain        = "vpc"
  depends_on    = [aws_internet_gateway.gw]
 }


#security groups

resource "aws_security_group" "application-sg" {
  name        = "acme-application-sg"
  description = "PErmite la entrada de trafico http y https solo desde el balanceador "
  vpc_id      = aws_vpc.acme-vpc.id


  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.balancer-sg.id]  # Permitir tráfico http solo del balanceador
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    security_groups = [aws_security_group.balancer-sg.id]  # Permitir tráfico http solo del balanceador
  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Permitir tráfico SSH desde cualquier dirección
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Permitir todo el tráfico de salida
  }
}

resource "aws_security_group" "balancer-sg" {
  name        = "acme-balancer-sg"
  description = "sg para el balanceador"
  vpc_id      = aws_vpc.acme-vpc.id



  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]

  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]  # Permitir todo el tráfico de salida
  }

}

#un target group para cada protocolo web
resource "aws_lb_target_group" "tg-http" {
  name     = "tg-http"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.acme-vpc.id
}
resource "aws_lb_target_group" "tg-https" {
  name     = "tg-https"
  port     = 443
  protocol = "HTTPS"
  vpc_id   = aws_vpc.acme-vpc.id
}

#define el balanceador
resource "aws_lb" "balancer" {
  name               = "balanceador-acme"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.balancer-sg.id]
  subnets            = [aws_subnet.acme-subnet.id, aws_subnet.acme-subnet2.id]

  enable_deletion_protection = false #en falso para que terraform destroy lo elemine

}

#define la instancia EC2
resource "aws_instance" "application" {
  ami                    = "ami-0014ce3e52359afbd"
  instance_type          = "t3.micro"
  key_name               = "acme"	
  vpc_security_group_ids = [aws_security_group.application-sg.id]
  availability_zone = "eu-north-1a"
  associate_public_ip_address = true
  subnet_id = aws_subnet.acme-subnet.id

  #código para la puesta en marcha del servidor web apache y la instalación de mysql y wordpress
  user_data = <<-EOF
            #!/bin/bash
            sudo apt-get install -y software-properties-common
            sudo add-apt-repository -y ppa:ondrej/php # For latest PHP version
            sudo apt-get update
            sudo apt-get install -y php7.4 php7.4-mysql php7.4-curl php7.4-gd php7.4-mbstring php7.4-xml php7.4-zip php7.4-xmlrpc

            
            
            sudo apt-get install -y mysql-server
            sudo mysql_secure_installation <<DELIMITADOR

              y
              $acmepatatas
              $acmepatatas
              y
              y
              y
              y
              DELIMITADOR
            
            sudo mysql -uroot -p$acmepatatas -e "CREATE DATABASE wordpress DEFAULT CHARACTER SET utf8 COLLATE utf8_unicode_ci;"
            sudo mysql -uroot -p$acmepatatas -e "CREATE USER 'wordpressuser'@'localhost' IDENTIFIED BY 'wordpresspass';"
            sudo mysql -uroot -p$acmepatatas -e "GRANT ALL ON wordpress.* TO 'wordpressuser'@'localhost';"
            sudo mysql -uroot -p$acmepatatas -e "FLUSH PRIVILEGES;"

            
            sudo apt-get install -y apache2
            sudo a2enmod rewrite
            sudo systemctl restart apache2

            
              sudo rm -rf /var/www/html/*
              sudo wget -c -O /tmp/latest.tar.gz https://wordpress.org/latest.tar.gz
              sudo tar -xzvf /tmp/latest.tar.gz -C /var/www/html --strip-components=1
              sudo chown -R www-data:www-data /var/www/html/
              sudo cp /var/www/html/wp-config-sample.php /var/www/html/wp-config.php
              sudo sed -i "s/wordpress/wordpress/g" /var/www/html/wp-config.php
              sudo sed -i "s/wordpressuser/wordpressuser/g" /var/www/html/wp-config.php
              sudo sed -i "s/wordpresspass/password/g" /var/www/html/wp-config.php
              sudo systemctl restart apache2

            
            EOF
}

#enlaza los target foups a la instancia ec2
resource "aws_lb_target_group_attachment" "application-http" {
  target_group_arn = aws_lb_target_group.tg-http.arn
  target_id        = aws_instance.application.id
  port             = 80
}
resource "aws_lb_target_group_attachment" "application-https" {
  target_group_arn = aws_lb_target_group.tg-https.arn
  target_id        = aws_instance.application.id
  port             = 443
}

#resource "aws_lb_listener" "https-listener" {
 # load_balancer_arn = aws_lb.balancer.arn
 # port              = "443"
  #protocol          = "HTTPS"
  
  #default_action {
   # type             = "forward"
    #target_group_arn = aws_lb_target_group.tg-https.arn
  #}
#} comentado porque da problemas con los certificados ssl, ya que no tengo uno

#define el listener par ael balanceador de carga
resource "aws_lb_listener" "https-listener" {
  load_balancer_arn = aws_lb.balancer.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.tg-http.arn
  }
}
