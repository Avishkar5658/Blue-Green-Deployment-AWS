<div align="center">

# 🚀 AWS Blue-Green Deployment with Canary Traffic Shifting

### Release a new website version safely using Amazon EC2, Application Load Balancer, and weighted target groups.

![AWS](https://img.shields.io/badge/Cloud-AWS-orange?logo=amazonaws&logoColor=white)
![EC2](https://img.shields.io/badge/Compute-EC2-FF9900?logo=amazonec2&logoColor=white)
![Load Balancer](https://img.shields.io/badge/Traffic-Application%20Load%20Balancer-8C4FFF)
![Deployment](https://img.shields.io/badge/Strategy-Blue--Green%20%2B%20Canary-167D3F)
![Level](https://img.shields.io/badge/Level-Beginner-blue)

**Goal:** Deploy Version 2 alongside Version 1, test it with a small percentage of traffic, and switch traffic to the new version without intentionally taking the website offline.

</div>

---

## 📌 Project Overview

This hands-on AWS project demonstrates a safer way to release a new website version. Two Amazon EC2 instances host separate versions of a simple website:

- 🔵 **Blue — Version 1:** the current version.
- 🟢 **Green — Version 2:** the new version being tested.
- ⚖️ **Application Load Balancer (ALB):** sends requests to the target groups according to configured weights.

Traffic is gradually shifted from Blue to Green. If the new version works correctly, Green receives all traffic. If a problem occurs, traffic can be routed back to Blue.

> **Important:** This lab demonstrates weighted traffic shifting and a rollback path. Zero downtime depends on application health, configuration, and successful testing; it is not guaranteed by the architecture alone.

## 🎯 What You'll Learn

- Create a custom Amazon VPC with two public subnets in different Availability Zones.
- Configure an Internet Gateway, route table, and security group.
- Launch EC2 instances and configure Apache using EC2 User Data.
- Register instances in separate target groups.
- Create an internet-facing Application Load Balancer.
- Configure weighted forwarding rules for a canary release.
- Perform a full traffic cutover and a rollback.
- Troubleshoot common load-balancer and target-health issues.

## 🏗️ Architecture

```text
                          Users / Web Browser
                                  |
                                  | HTTP : 80
                                  v
                   +------------------------------+
                   |   BlueGreen-ALB (Internet)   |
                   | Application Load Balancer    |
                   +------------------------------+
                                  |
                      Weighted forwarding rule
                         /                 \
                   80% /                   \ 20%
                      v                     v
              +---------------+     +---------------+
              |    TG-Blue    |     |   TG-Green    |
              +---------------+     +---------------+
                      |                     |
                      v                     v
              +---------------+     +---------------+
              |  Blue-Server  |     | Green-Server  |
              |  Version 1    |     |  Version 2    |
              |  Apache : 80  |     |  Apache : 80  |
              +---------------+     +---------------+
                Public-1 / AZ-a       Public-2 / AZ-b

                 Both subnets are in BG-VPC
```

**Traffic flow:** Browser → ALB listener on HTTP port 80 → weighted target group → EC2 web server.

### AWS Resources

| Resource | Name | Configuration |
|---|---|---|
| VPC | `BG-VPC` | `10.0.0.0/16` |
| Public subnet 1 | `Public-1` | `us-east-1a` · `10.0.1.0/24` |
| Public subnet 2 | `Public-2` | `us-east-1b` · `10.0.2.0/24` |
| Internet Gateway | `BG-IGW` | Attached to `BG-VPC` |
| Route table | `BG-RT` | Default route `0.0.0.0/0` → Internet Gateway |
| Security group | `Web-SG` | HTTP port 80 inbound |
| Blue EC2 | `Blue-Server` | `t3.micro`, Amazon Linux 2023 |
| Green EC2 | `Green-Server` | `t3.micro`, Amazon Linux 2023 |
| Blue target group | `TG-Blue` | HTTP port 80 → Blue instance |
| Green target group | `TG-Green` | HTTP port 80 → Green instance |
| Load balancer | `BlueGreen-ALB` | Internet-facing ALB, HTTP listener on port 80 |

**AWS Region:** `us-east-1` (US East — N. Virginia)

## 🔄 Deployment Stages

| Stage | Blue weight | Green weight | Expected result |
|---|---:|---:|---|
| Initial deployment | 100% | 0% | Users see Version 1 (Blue) |
| Canary release | 80% | 20% | Most requests go to Blue; some go to Green |
| Full cutover | 0% | 100% | Requests go to Version 2 (Green) |
| Rollback | 100% | 0% | Traffic returns to Blue |

> Weighted routing distributes requests according to configured weights over time. It does not guarantee that exactly 20 out of every 100 individual browser refreshes will show Green.

## 🛠️ Prerequisites

- An AWS account or an authorized AWS lab environment (for example, KodeKloud Labs).
- AWS Console access with permissions to create VPC, EC2, target groups, and load balancers.
- Region set to `us-east-1`.
- A browser for testing the ALB DNS name.

## 🚀 Implementation Guide

### 1. Create the VPC and networking

1. Open **VPC → Create VPC → VPC only**.
2. Create `BG-VPC` with IPv4 CIDR `10.0.0.0/16`.
3. Create two subnets:
   - `Public-1`: `10.0.1.0/24`, Availability Zone `us-east-1a`
   - `Public-2`: `10.0.2.0/24`, Availability Zone `us-east-1b`
4. Enable **auto-assign public IPv4 address** for both subnets.
5. Create `BG-IGW` and attach it to `BG-VPC`.
6. Create route table `BG-RT`.
7. Add route `0.0.0.0/0` with target `BG-IGW`.
8. Associate both public subnets with `BG-RT`.

### 2. Create the security group

Create `Web-SG` in `BG-VPC` with this inbound rule:

| Type | Protocol | Port | Source |
|---|---|---:|---|
| HTTP | TCP | 80 | `0.0.0.0/0` |

For a production setup, prefer restricting access where possible and separating the ALB-facing rules from instance-facing rules. This beginner lab uses a shared security group for simplicity.

### 3. Launch the Blue server (Version 1)

In **EC2 → Launch instance**:

- Name: `Blue-Server`
- AMI: Amazon Linux 2023
- Instance type: `t3.micro`
- VPC: `BG-VPC`
- Subnet: `Public-1`
- Security group: `Web-SG`
- User Data: paste the script below.

```bash
#!/bin/bash
yum update -y
yum install -y httpd
systemctl enable --now httpd

cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
  <body style="background-color:blue;color:white;text-align:center;font-family:Arial">
    <h1>VERSION 1 (BLUE)</h1>
    <p>Blue environment — current release</p>
  </body>
</html>
EOF
```

Launch the instance and wait until its status checks pass.

### 4. Launch the Green server (Version 2)

Launch another EC2 instance using the same AMI, instance type, VPC, and security group, but choose subnet `Public-2`.

Use this User Data script:

```bash
#!/bin/bash
yum update -y
yum install -y httpd
systemctl enable --now httpd

cat > /var/www/html/index.html <<'EOF'
<!DOCTYPE html>
<html>
  <body style="background-color:green;color:white;text-align:center;font-family:Arial">
    <h1>VERSION 2 (GREEN)</h1>
    <p>Green environment — new release</p>
  </body>
</html>
EOF
```

Launch it as `Green-Server`. Wait until both EC2 instances pass their status checks.

### 5. Create the target groups

Open **EC2 → Target Groups → Create target group** and create:

- `TG-Blue`: target type **Instances**, protocol HTTP, port 80, VPC `BG-VPC`; register `Blue-Server`.
- `TG-Green`: target type **Instances**, protocol HTTP, port 80, VPC `BG-VPC`; register `Green-Server`.

Wait until the registered targets show **Healthy** before proceeding.

### 6. Create the Application Load Balancer

1. Open **EC2 → Load Balancers → Create load balancer**.
2. Select **Application Load Balancer**.
3. Name it `BlueGreen-ALB`.
4. Scheme: **Internet-facing**.
5. Select VPC `BG-VPC` and both `Public-1` and `Public-2` in their respective Availability Zones.
6. Select a security group that permits inbound HTTP port 80.
7. Configure an HTTP listener on port `80` with the default action forwarding to `TG-Blue`.
8. Create the ALB and wait for its state to become **Active**.
9. Copy its DNS name and open `http://<ALB-DNS-NAME>` in a browser.

**Expected initial output:** `VERSION 1 (BLUE)`

### 7. Shift traffic to Green (canary release)

1. Open **EC2 → Load Balancers → BlueGreen-ALB → Listeners and rules**.
2. Select the HTTP:80 listener and edit its forwarding rule.
3. Configure weighted forwarding:
   - `TG-Blue`: **80**
   - `TG-Green`: **20**
4. Save the rule and allow a short time for it to take effect.
5. Refresh the ALB URL multiple times, preferably in a private/incognito browser window.

**Expected result:** Blue appears more often, while Green appears occasionally. The distribution is probabilistic, so a small number of refreshes may not match the configured ratio.

### 8. Complete the cutover to Green

After verifying the Green version and its health:

1. Edit the ALB listener's weighted forwarding rule.
2. Set `TG-Blue` weight to **0**.
3. Set `TG-Green` weight to **100**.
4. Save the changes and test the ALB DNS name again.

**Expected output:** `VERSION 2 (GREEN)`

### 9. Roll back if needed

If Green has a problem, edit the same forwarding rule and restore:

- `TG-Blue`: **100**
- `TG-Green`: **0**

Save the rule and verify that the ALB serves the Blue version again. Keep Blue available until the new release has been validated.

## ✅ Validation Checklist

- [ ] Both EC2 instances are running and pass status checks.
- [ ] `TG-Blue` and `TG-Green` targets are healthy.
- [ ] The ALB state is `Active`.
- [ ] Initial traffic shows Version 1 (Blue).
- [ ] Canary rule is configured as 80% Blue / 20% Green.
- [ ] Green is reachable through the ALB during canary testing.
- [ ] Full cutover shows Version 2 (Green).
- [ ] Rollback to Blue has been tested or documented.
- [ ] AWS resources are deleted when the lab is finished.

## 🧰 Troubleshooting

| Problem | What to check |
|---|---|
| Website does not open | Use `http://`, confirm the ALB is `Active`, and check inbound port 80 rules. |
| ALB returns 502/503 | Check target-group health, target registration, listener forwarding, and instance web-server status. |
| Target is unhealthy | Verify User Data ran successfully, Apache is active, and the security group allows the ALB to reach port 80. |
| Only one version appears | Confirm the weights are saved correctly; refresh more times or use an incognito window. |
| ALB creation fails | Ensure the ALB uses at least two subnets in different Availability Zones. |

If you can connect to an instance, check Apache with:

```bash
sudo systemctl status httpd
sudo cat /var/www/html/index.html
```

On Amazon Linux 2023, Apache's service name is `httpd`.

## 💰 Clean Up AWS Resources

**Important:** AWS resources may incur charges while they are running. When you finish the lab, remove resources you no longer need.

Suggested cleanup order:

1. Delete `BlueGreen-ALB`.
2. Delete `TG-Blue` and `TG-Green`.
3. Terminate `Blue-Server` and `Green-Server`.
4. Delete `Web-SG` when it is no longer in use.
5. Delete `BG-RT` after removing subnet associations.
6. Detach and delete `BG-IGW`.
7. Delete `Public-1` and `Public-2`.
8. Delete `BG-VPC`.

Check that no other resources depend on these components before deleting them.

## 🧠 Key Concepts for Interviews

**What is Blue-Green Deployment?**  
A deployment strategy that keeps the current version (Blue) and the new version (Green) in separate environments so traffic can be switched between them.

**What is a Canary Deployment?**  
A release approach that exposes a new version to a small portion of traffic first, checks its behavior, and increases traffic if it performs well.

**What does the ALB do in this project?**  
The Application Load Balancer provides a single entry point and forwards requests to target groups using the configured weights.

**Why use two target groups?**  
They keep the Blue and Green server registrations separate, allowing traffic to be controlled independently.

**How do you roll back?**  
Set the forwarding weights back to 100 for `TG-Blue` and 0 for `TG-Green`.

## 📚 Project Summary

This project provides practical experience with AWS networking, EC2 User Data, Apache, target groups, Application Load Balancers, weighted forwarding, canary releases, and rollback procedures. It demonstrates how to reduce release risk by testing a new version before directing all traffic to it.

---

<div align="center">

**Built as a hands-on AWS & Cloud/DevOps learning project** ☁️

*Learn • Deploy • Test • Roll Back Safely*

</div>
