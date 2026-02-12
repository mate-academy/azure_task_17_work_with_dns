#!/bin/bash

# Script to silently install and start the todo web app on the virtual machine. 
# Note that all commands bellow are without sudo - that's because extention mechanism 
# runs scripts under root user. 

# install system updates and isntall python3-pip package using apt. '-yq' flags are 
# used to suppress any interactive prompts - we won't be able to confirm operation 
# when running the script as VM extention.  
apt-get update -yq
apt-get install python3-pip -yq

# Create a directory for the app and download the files. 
mkdir /app 
# make sure to uncomment the line bellow and update the link with your GitHub username
cd /app
rm -rf /app/repo
git clone https://github.com/KyryloKilin/azure_task_17_work_with_dns.git repo
cp -r /app/repo/app/* /app

# create a service for the app via systemctl and start the app
mv /app/todoapp.service /etc/systemd/system/
systemctl daemon-reload
systemctl start todoapp
systemctl enable todoapp
