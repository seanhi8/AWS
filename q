import time

for repository in repositories:
    # Create a To Do Later list
    to_be_processed_images = []
    # Maximum polling time in seconds (e.g., 10 minutes)
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
                status = image['imageScanStatus']['status']

                # 状态为 COMPLETE 时直接输出日志
                if status == "COMPLETE":
                    print(f"COMPLETE {repository['repositoryName']}/{image['imageTags'][0]}")

                # 状态为 IN_PROGRESS 或 PENDING 时添加到稍后处理列表
                elif status in ["IN_PROGRESS", "PENDING"]:
                    to_be_processed_images.append({
                        'registryId': repository['registryId'],
                        'repositoryName': repository['repositoryName'],
                        'imageTag': image['imageTags'][0]
                    })

                # 状态为其他错误类型时输出日志为 ERROR
                elif status in ["FAILED", "ACTIVE", "SCAN_ELIGIBILITY_EXPIRED", "UNSUPPORTED_IMAGE"]:
                    print(f"ERROR {repository['repositoryName']}/{image['imageTags'][0]}: {status}")

    # Polling loop with timeout
    while to_be_processed_images and (time.time() - polling_start_time < MAX_POLLING_TIME):
        time.sleep(30)  # Poll every 30 seconds

        # 遍历稍后处理列表中的每个镜像
        for image in to_be_processed_images[:]:  # 创建副本以便在循环中修改列表
            # 重新获取镜像的最新扫描状态
            updated_image = ecr_client.describe_images(
                registryId=image['registryId'],
                repositoryName=image['repositoryName'],
                imageIds=[{'imageTag': image['imageTag']}]
            )['imageDetails'][0]
            status = updated_image['imageScanStatus']['status']

            # 如果扫描状态为 COMPLETE，从列表中移除并输出日志
            if status == "COMPLETE":
                print(f"COMPLETE {image['repositoryName']}/{image['imageTag']}")
                to_be_processed_images.remove(image)

            # 如果扫描状态为其他错误类型，从列表中移除并输出日志为 ERROR
            elif status in ["FAILED", "ACTIVE", "SCAN_ELIGIBILITY_EXPIRED", "UNSUPPORTED_IMAGE"]:
                print(f"ERROR {image['repositoryName']}/{image['imageTag']}: {status}")
                to_be_processed_images.remove(image)

    # Check if timeout was reached
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
