//create provider run the login and regio where to launch the instancese
provider "aws" {
  region  = "ap-south-1"
  profile ="Neetesh"
}

//create key pairs 

resource "tls_private_key" "privatekey" {
  algorithm   = "RSA"
}

resource "aws_key_pair" "keypair" {
  key_name   = "terraformkey"
  public_key = "${tls_private_key.privatekey.public_key_openssh}"
    depends_on=[
                tls_private_key.privatekey
               ]
}

resource "local_file" "key" {
    content     = "${tls_private_key.privatekey.private_key_pem}"
    filename = "terraformkey.pem"
   depends_on=[aws_key_pair.keypair]
    
}
//create security group to use SSH

resource "aws_security_group" "sg_gp" {
  name        = "sg_gp"
  description = "Apply SSH"
  vpc_id      = "vpc-fba9b493"

  ingress {
    description = "TLS from VPC"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "sg_gp"
  }
}
//private key 
//resource create aws_instance
resource "aws_instance" "web" {
  ami           = "ami-0447a12f28fddb066"
  instance_type = "t2.micro"
  key_name="terraformkey" 
  security_groups=["sg_gp"]
//connect the operating system
 connection{
 	type="ssh"
	user= "ec2-user"
    	private_key ="${tls_private_key.privatekey.private_key_pem}"
    	host     = aws_instance.web.public_ip
}
// launch webserver

  provisioner "remote-exec" {
    inline = [
      "sudo yum install httpd  php git -y",
      "sudo systemctl restart httpd",
      "sudo systemctl enable httpd",
    ]
  }
  tags = {
    Name = "LINUX"
  }
}
//EBS volume creation
resource "aws_ebs_volume" "esb1" {
  availability_zone = aws_instance.web.availability_zone
  size              = 1
  tags = {
    Name = "mypd"
  }
}

resource "aws_volume_attachment" "ebs_att" {
	depends_on=[aws_ebs_volume.esb1]
  device_name = "/dev/sdh"
  volume_id   = "${aws_ebs_volume.esb1.id}"
  instance_id = "${aws_instance.web.id}"
  force_detach = true
}
resource "null_resource" "remote2"  {

depends_on = [
    aws_volume_attachment.ebs_att,
  ]
  connection {
    type     = "ssh"
    user     = "ec2-user"
    private_key = "${tls_private_key.privatekey.private_key_pem}"
    host     = aws_instance.web.public_ip
  }

provisioner "remote-exec" {
    inline = [
      "sudo mkfs.ext4  /dev/xvdh",
      "sudo mount  /dev/xvdh  /var/www/html",
      "sudo rm -rf /var/www/html/*",
      "sudo git clone https://github.com/imneeteeshyadav98/hmc_t1.git /var/www/html/",
    ]
  }
}
// create s3 bucket
resource "aws_s3_bucket" "neeteshbucket1234"{
	bucket = "neeteshbucket1234"
  	acl    = "public-read"
	versioning{enabled=true}
}
resource "aws_s3_bucket_object" "fileupload" {
  key        = "static_images"
  bucket     = "${aws_s3_bucket.neeteshbucket1234.id}"
  acl="public-read"
  source     = "1.png"
  etag=filemd5("1.png")
}
locals {
  s3_origin_id = "myS3Origin"
}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = "${aws_s3_bucket.neeteshbucket1234.bucket_regional_domain_name}"
    origin_id   = "${local.s3_origin_id}"
  }

  enabled             = true
  is_ipv6_enabled     = true
  comment             = "Imges"
  default_root_object = "static_images"
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }
	viewer_protocol_policy = "allow-all"
    	min_ttl                = 0
    	default_ttl            = 3600
    	max_ttl                = 86400
}
ordered_cache_behavior {
    path_pattern     = "/content/immutable/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD", "OPTIONS"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false
      headers      = ["Origin"]

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 86400
    max_ttl                = 31536000
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  //# Cache behavior with precedence 1
  ordered_cache_behavior {
    path_pattern     = "/content/*"
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "${local.s3_origin_id}"

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
    compress               = true
    viewer_protocol_policy = "redirect-to-https"
  }

  price_class = "PriceClass_200"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["IN"]
    }
  }

  tags = {
    Environment = "production"
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }
 connection{
 	type="ssh"
	user= "ec2-user"
    	private_key ="${tls_private_key.privatekey.private_key_pem}"
    	host     = aws_instance.web.public_ip
}
provisioner "remote-exec" {

            inline  = [

                // "sudo su << \"EOF\" \n echo \"<img src='${self.domain_name}'>\" >> /var/www/html/index.php \n \"EOF\""

                "sudo su << EOF",

                "echo \"<center><img src='http://${self.domain_name}/${aws_s3_bucket_object.fileupload.key}' height='100px' width='200px'></center>\" >> /var/www/html/index.php",

                "EOF"

            ]

        }
}

resource "null_resource" "nulllocal1"  {


depends_on = [
    null_resource.remote2,aws_cloudfront_distribution.s3_distribution
  ]

	provisioner "local-exec" {
	    command = "firefox  ${aws_instance.web.public_ip}"
  	}
}
