import time

for repository in repositories:
    # 创建稍后处理列表
    to_be_processed_images = []
    # 最大轮询时间（以秒为单位，例如10分钟）
    MAX_POLLING_TIME = 600  
    polling_start_time = time.time()

    describeimage_paginator = ecr_client.get_paginator('describe_images')
    for response_describeimagepaginator in describeimage_paginator.paginate(
        registryId=repository['registryId'],
        repositoryName=repository['repositoryName']
    ):
        for image in response_describeimagepaginator['imageDetails']:
            # 检查镜像是否需要扫描
            if ('imageTags' in image) and repository['repositoryName'] not in noscan_images:
                try:
                    status = image['imageScanStatus']['status']
                except KeyError:
                    # 当扫描请求超出限制时，将其视为错误类型
                    print(f"ScanOver {repository['repositoryName']}/{image['imageTags'][0]}: LimitExceededException")
                    continue  # 跳过该镜像，继续处理下一个

                except ClientError as e:
                    # 检查是否为配额超限错误
                    if e.response['Error']['Code'] == 'LimitExceededException':
                        # 如果是配额超限错误，打印一条警告信息并等待
                        print(f"Warning: Scan limit exceeded for {repository_name}/{image_id['imageTag']}: {e.response['Error']['Message']}")
                        time.sleep(RETRY_DELAY)  # 等待指定时间后重试
                        retries += 1  # 增加重试次数
                    else:
                        # 如果是其他类型的错误，抛出异常
                        raise

                # 如果状态为 COMPLETE，直接输出日志
                if status == "COMPLETE":
                    print(f"COMPLETE {repository['repositoryName']}/{image['imageTags'][0]}")

                # 如果状态为 IN_PROGRESS 或 PENDING，添加到稍后处理列表
                elif status in ["IN_PROGRESS", "PENDING"]:
                    to_be_processed_images.append({
                        'registryId': repository['registryId'],
                        'repositoryName': repository['repositoryName'],
                        'imageTag': image['imageTags'][0]
                    })

                # 如果状态为其他错误类型，输出日志为 ERROR
                elif status in ["FAILED", "ACTIVE", "SCAN_ELIGIBILITY_EXPIRED", "UNSUPPORTED_IMAGE"]:
                    print(f"ERROR {repository['repositoryName']}/{image['imageTags'][0]}: {status}")

    # 带有超时的轮询循环
    while to_be_processed_images and (time.time() - polling_start_time < MAX_POLLING_TIME):
        time.sleep(30)  # 每30秒轮询一次

        # 遍历稍后处理列表中的每个镜像
        for image in to_be_processed_images[:]:  # 创建副本以便在循环中修改列表
            try:
                # 重新获取镜像的最新扫描状态
                updated_image = ecr_client.describe_images(
                    registryId=image['registryId'],
                    repositoryName=image['repositoryName'],
                    imageIds=[{'imageTag': image['imageTag']}]
                )['imageDetails'][0]
                status = updated_image['imageScanStatus']['status']
            except ecr_client.exceptions.LimitExceededException:
                print(f"ScanOver {image['repositoryName']}/{image['imageTag']}: LimitExceededException")
                to_be_processed_images.remove(image)
                continue

            except ClientError as e:
                # 检查是否为配额超限错误
                if e.response['Error']['Code'] == 'LimitExceededException':
                    # 如果是配额超限错误，打印一条警告信息并等待
                    print(f"Warning: Scan limit exceeded for {repository_name}/{image_id['imageTag']}: {e.response['Error']['Message']}")
                    time.sleep(RETRY_DELAY)  # 等待指定时间后重试
                    retries += 1  # 增加重试次数
                else:
                    # 如果是其他类型的错误，抛出异常
                    raise

            # 如果扫描状态为 COMPLETE，从列表中移除并输出日志
            if status == "COMPLETE":
                print(f"COMPLETE {image['repositoryName']}/{image['imageTag']}")
                to_be_processed_images.remove(image)

            # 如果扫描状态为其他错误类型，从列表中移除并输出日志为 ERROR
            elif status in ["FAILED", "ACTIVE", "SCAN_ELIGIBILITY_EXPIRED", "UNSUPPORTED_IMAGE"]:
                print(f"ERROR {image['repositoryName']}/{image['imageTag']}: {status}")
                to_be_processed_images.remove(image)

    # 检查是否达到超时
    if to_be_processed_images:
        print("Warning: Scanning timed out for some images.")
    else:
        print("Scanning complete")



import time

for repository in repositories:
    to_be_processed_images = []
    MAX_POLLING_TIME = 600  
    polling_start_time = time.time()

    describeimage_paginator = ecr_client.get_paginator('describe_images')
    for response_describeimagepaginator in describeimage_paginator.paginate(
        registryId=repository['registryId'],
        repositoryName=repository['repositoryName']
    ):
        for image in response_describeimagepaginator['imageDetails']:
            if ('imageTags' in image) and repository['repositoryName'] not in noscan_images:
                status = image['imageScanStatus']['status']
                
                if status == "COMPLETE":
                    print(f"COMPLETE {repository['repositoryName']}/{image['imageTags'][0]}")
                elif status in ["IN_PROGRESS", "PENDING"]:
                    to_be_processed_images.append({
                        'registryId': repository['registryId'],
                        'repositoryName': repository['repositoryName'],
                        'imageTag': image['imageTags'][0]
                    })
                elif status in ["FAILED", "ACTIVE", "SCAN_ELIGIBILITY_EXPIRED", "UNSUPPORTED_IMAGE"]:
                    print(f"ERROR {repository['repositoryName']}/{image['imageTags'][0]}: {status}")

    while to_be_processed_images and (time.time() - polling_start_time < MAX_POLLING_TIME):
        time.sleep(30)
        for image in to_be_processed_images[:]:
            updated_image = ecr_client.describe_images(
                registryId=image['registryId'],
                repositoryName=image['repositoryName'],
                imageIds=[{'imageTag': image['imageTag']}]
            )['imageDetails'][0]
            status = updated_image['imageScanStatus']['status']
            
            if status == "COMPLETE":
                print(f"COMPLETE {image['repositoryName']}/{image['imageTag']}")
                to_be_processed_images.remove(image)
            elif status in ["FAILED", "ACTIVE", "SCAN_ELIGIBILITY_EXPIRED", "UNSUPPORTED_IMAGE"]:
                print(f"ERROR {image['repositoryName']}/{image['imageTag']}: {status}")
                to_be_processed_images.remove(image)

    if to_be_processed_images:
        print("Warning: Scanning timed out for some images.")
    else:
        print("Scanning complete")
