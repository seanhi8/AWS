import time

# 获取镜像列表
for repository in repositories:
    # 创建稍后处理列表
    to_be_processed_images = []

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

    # 定期轮询稍后处理列表，直到列表为空
    while to_be_processed_images:
        time.sleep(30)  # 每隔 30 秒轮询一次

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

            # 状态为 IN_PROGRESS 或 PENDING 时保持在列表中，不进行删除

    print("扫描结束")
