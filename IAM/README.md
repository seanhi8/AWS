# Related knowledges

## VPC

### 概述

1. [官方文档](https://docs.aws.amazon.com/zh_cn/vpc/latest/userguide/what-is-amazon-vpc.html)

### CIDR

[CIDR计算器](http://www.subnet-calculator.com/cidr.php)

### VPC中的数据保护

1. AWS建议：
   - 对每个账户使用 Multi-Factor Authentication (MFA)。
   - 使用 SSL/TLS 与 AWS 资源进行通信。
   - 使用 AWS CloudTrail 设置 API 和用户活动日志记录。
   - 使用高级托管安全服务（例如 Amazon Macie），它有助于发现和保护存储在 Amazon S3 中的个人数据。
 
 2. 提高和监控VPC的安全性的四种服务：
    - 安全组：安全组用作相关 Amazon EC2 实例的防火墙，可在实例级别控制入站和出站的数据流。
    - 网络访问控制列表 (ACL)：用作关联的子网的防火墙，在子网级别同时控制入站和出站流量。
    - 流日志：流日志捕获有关在您的 VPC 中传入和传出网络接口的 IP 流量的信息。您可以为 VPC、子网或各个网络接口创建流日志。流日志数据将发布到 CloudWatch Logs 或 Amazon S3，这可帮助您诊断过于严格或过于宽松的安全组和网络 ACL 规则。
    - 流量镜像：您可以从 Amazon EC2 实例的弹性网络接口复制网络流量。然后将流量发送到带外安全和监控设备。

### 相关习题

1. 一家公司需要记录私有子网中所有IP包（源，目标，协议），最佳解决方案是什么？（#1-8）
   - [ ] A. 使用[VPC flow logs](https://docs.aws.amazon.com/zh_cn/vpc/latest/userguide/flow-logs.html)。
   - [ ] B. 使用EC2上的`source destination checkout`。
   - [ ] C. 使用[AWS CloudTrail](https://docs.aws.amazon.com/zh_cn/awscloudtrail/latest/userguide/cloudtrail-user-guide.html)并且使用S3存储日志文件。
   - [ ] D. 使用[Amazon CloudWatch](https://docs.aws.amazon.com/zh_cn/AmazonCloudWatch/latest/monitoring/WhatIsCloudWatch.html)进行监控
   
2. 一个应用运行在私有子网的EC2实例上，这个应用需要读写`Amazon Kinesis Data Streams`上的数据。但是该公司要求读取数据的流不能流向万维网（Internet），最佳解决方案是什么？（#1-39）
   - [ ] A. 在一个共有子网中配置一个[NAT网关（NAT Gateway）](https://docs.aws.amazon.com/zh_cn/vpc/latest/userguide/vpc-nat-gateway.html)并且将读写流路由到`Kinesis`服务上。
   - [ ] B. 为`Kinesis`配置一个[网关 VPC 终端节点（Gateway VPC Endpoint）](https://docs.aws.amazon.com/zh_cn/vpc/latest/userguide/vpce-gateway.html)并且通过其将读写流路由到`Kinesis`服务上。
   - [ ] C. 为`Kinesis`配置一个[接口 VPC 终端节点（Interface VPC Endpoint）](https://docs.aws.amazon.com/zh_cn/vpc/latest/userguide/vpce-interface.html)并且通过其将读写流路由到`Kinesis`服务上。
   - [ ] D. 为`Kinesis`配置一个[AWS Direct Connect 虚拟接口](https://docs.aws.amazon.com/zh_cn/directconnect/latest/UserGuide/WorkingWithVirtualInterfaces.html)并且通过其将读写流路由到`Kinesis`服务上。

3. 你启动了一个实例并且将它用作在公共子网中NAT设备。接着你修改路由表，在私有子网中将此NAT设备变更成互联网流的目标，当你试图使用此私有子网中的实例去连接外网（outbount connection）,你发现这并不成功，什么操作能解决这个问题？（#1-47）
   - [ ] A. 为这个NAT实例添加[弹性网络接口（Elasitc Network Interface）](https://docs.aws.amazon.com/zh_cn/AWSEC2/latest/UserGuide/using-eni.html)，并把它加入到私有子网中。
   - [ ] B. 为这个NAT实例添加[弹性IP地址（Elasitc IP Address）](hhttps://docs.aws.amazon.com/zh_cn/AWSEC2/latest/UserGuide/elastic-ip-addresses-eip.html)。
   - [ ] C. 为这个NAT实例添加另外一个弹性网络接口（Elasitc Network Interface）并把它加入到公有子网中。
   - [ ] D. 停止这个NAT实例上的[Source/Destination Check](https://docs.aws.amazon.com/zh_cn/vpc/latest/userguide/VPC_NAT_Instance.html)功能。

## AWS Outposts

### 概述

AWS Outposts 是一项完全托管的服务，可将 AWS 基础设施、AWS 服务、API 和工具扩展到几乎任何数据中心、共处空间或本地设施，以实现真正一致的混合体验。AWS Outposts 非常适合**需要低延迟访问本地系统、本地数据处理或本地数据存储的工作负载**。

### 应用

AWS Outposts 解决了多种行业中的低延迟应用程序需求和本地数据处理需求。
