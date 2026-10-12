#!/bin/bash
yum update -y
yum install -y httpd
systemctl start httpd
systemctl enable httpd
echo '<html><body style="background-color:blue; color:white"><h1>🟦 VERSION 1 (BLUE)</h1></body></html>' > /var/www/html/index.html
