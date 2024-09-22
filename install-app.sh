#!/bin/bash

# Script to silently install and start the todo web app on the virtual machine.
# Note that all commands bellow are without sudo - that's because extention mechanism 
# runs scripts under root user. 

# install system updates and isntall python3-pip package using apt. '-yq' flags are
# used to suppress any interactive prompts - we won't be able to confirm operation
# when running the script as VM extention.  
apt update -yq
apt install python3-pip -yq

# Create a directory for the app and download the files. 
mkdir /app 
# make sure to uncomment the line bellow and update the link with your GitHub username
cd ~
git clone https://github.com/YegorVolkov/azure_task_17_work_with_dns.git
cp -r azure_task_17_work_with_dns/app/* /app

# ensure it will actually work
cd /app
chmod +x start.sh

# create a service for the app via systemctl and start the app
mv /app/todoapp.service /etc/systemd/system/
systemctl daemon-reload
systemctl start todoapp
systemctl enable todoapp
