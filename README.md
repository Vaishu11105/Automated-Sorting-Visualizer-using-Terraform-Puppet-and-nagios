These are the files including main.tf file for terraform . 
Apart from this create a IAM user on AWS , including Commond Line Interface and Administrator access.
Also create a key pair (.pem) file and place it in this folder.
After that:
1.	Start the stopped EC2 instances (GUI or AWS CLI).
2.	Get their current public IPs.
3.	SSH into puppet_server, web_server, nagios_server (three separate local terminals).
4.	Ensure puppet master is running, copy app.zip (if needed), sign certs and run puppet agent on web.
5.	Ensure Nginx serves your app and Nagios monitors the web server.
6.	Troubleshoot minimal common failures.

Open three local terminals (PowerShell / Terminal), one per server
We’ll keep them separate so you can run commands simultaneously and follow status easily.
Ssh into the terminals
SSH into puppet_server (Local → Puppet Server terminal)
ssh -i "C:\Users\vaish\Desktop\terraform-folder\Devops-1.pem" ubuntu@<PUPPET_PUBLIC_IP>
Check Puppet server status:
# become root
sudo -i
# check puppetserver
systemctl status puppetserver --no-pager
# check java/jvm memory errors (puppetserver uses JVM)
sudo journalctl -u puppetserver -n 100 --no-pager
exit from root
SSH into web_server (Local → Web Server terminal)
ssh -i "C:\Users\vaish\Desktop\terraform-folder\Devops-1.pem" ubuntu@<WEB_PUBLIC_IP>
On the web_server do these checks:
1.	Ensure /etc/hosts maps puppet hostname:
# check entry
grep -E "puppet" /etc/hosts || echo "<PUPPET_PRIVATE_IP> puppet" | sudo tee -a /etc/hosts
# replace <PUPPET_PRIVATE_IP> with puppet_server private IP (10.x.x.x)
2.	Check Puppet agent service and version:
sudo /opt/puppetlabs/bin/puppet --version
# run puppet agent once to request cert (expected to fail until signed)
sudo /opt/puppetlabs/bin/puppet agent -t || true
3.	Check Nginx status:
sudo systemctl status nginx --no-pager
# if not running, start it:
sudo systemctl start nginx
sudo systemctl enable nginx
4.	Verify web root files:
ls -la /var/www/html
curl -I http://localhost
curl http://localhost
SSH into nagios_server (Local → Nagios Server terminal)
ssh -i "C:\Users\vaish\Desktop\terraform-folder\Devops-1.pem" ubuntu@<NAGIOS_PUBLIC_IP>
On nagios_server:
# check nagios service
sudo systemctl status nagios4 apache2 --no-pager
# if stopped, start and enable
sudo systemctl start apache2 nagios4
sudo systemctl enable apache2 nagios4
# open firewall if UFW used
sudo ufw allow 80/tcp
Then in a browser (local machine), open:
http://<NAGIOS_PUBLIC_IP>/nagios4
Sign Puppet certificates (on puppet_server)
After the web agent run (step E.2) it should have created a certificate request.
On puppet_server terminal:
# list pending CSRs
sudo /opt/puppetlabs/bin/puppetserver ca list --all
# sign all (if you trust these)
sudo /opt/puppetlabs/bin/puppetserver ca sign --all
# or sign specific (replace CERTNAME with what puppet agent printed earlier)
sudo /opt/puppetlabs/bin/puppetserver ca sign --certname ip-10-0-1-127.ap-south-1.compute.internal
Then back on web_server terminal, run agent again:
sudo /opt/puppetlabs/bin/puppet agent -t
Verify web app deployed (web_server)
On web_server:
# check files exist
ls -la /var/www/html
# ensure permissions and ownership
sudo chown -R www-data:www-data /var/www/html
sudo chmod -R 755 /var/www/html
# test locally
curl -I http://localhost
curl http://localhost
From your laptop's browser open:
http://<WEB_PUBLIC_IP>
You should see the app page (not Nginx default).
Ensure NRPE is running on web_server and Nagios can check it
On web_server:
sudo systemctl status nagios-nrpe-server
# restart if needed
sudo systemctl restart nagios-nrpe-server


Check allowed_hosts in NRPE config
Open the NRPE config on the web server:
sudo nano /etc/nagios/nrpe.cfg
Find:
allowed_hosts=127.0.0.1
Change it to:
allowed_hosts=127.0.0.1,10.0.1.63
👉 10.0.1.63 is your Nagios Server private IP.(change to nagios server private ip)

On nagios_server, test remote NRPE:
/usr/lib/nagios/plugins/check_nrpe -H <WEB_PRIVATE_IP>
# test a specific check
/usr/lib/nagios/plugins/check_nrpe -H <WEB_PRIVATE_IP> -c check_disk
If Nagios complains about config, on nagios_server re-verify:
sudo /usr/sbin/nagios4 -v /etc/nagios4/nagios.cfg
sudo systemctl restart nagios4
Open Nagios web UI:
http://<NAGIOS_PUBLIC_IP>/nagios4
Check the host web-server and its services.
If public IPs changed — update any manual /etc/hosts entries
If you used /etc/hosts with public IP addresses earlier, update them. On each server that needs to resolve puppet (web & nagios):
On web_server and nagios_server:
sudo sed -i '/puppet/d' /etc/hosts
echo "<PUPPET_PRIVATE_IP> puppet" | sudo tee -a /etc/hosts
# replace <PUPPET_PRIVATE_IP> with puppet_server private IP (10.x.x.x)


