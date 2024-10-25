import time

# Get Image List in Repository
for repository in repositories:
    scansha = []
    tagged_images = []

    describeimage_paginator = ecr_client.get_paginator('describe_images')
    for response_describeimagepaginator in describeimage_paginator.paginate(
        registryId=repository['registryId'],
        repositoryName=repository['repositoryName']
    ):
        for image in response_describeimagepaginator['imageDetails']:
            # Scan Image with ImageTag
            if ('imageTags' in image) and repository['repositoryName'] not in noscan_images:
                # Check the scan status
                status = image['imageScanStatus']['status']

                # Wait until the scan status is no longer IN_PROGRESS
                while status == "IN_PROGRESS":
                    print(f"Scanning in progress for {image['repositoryName']}/{image['imageTags'][0]}...")
                    time.sleep(10)  # Wait for 10 seconds before checking again
                    # Re-fetch the image details to check the updated scan status
                    updated_image = ecr_client.describe_images(
                        registryId=repository['registryId'],
                        repositoryName=repository['repositoryName'],
                        imageIds=[{'imageTag': image['imageTags'][0]}]
                    )['imageDetails'][0]
                    status = updated_image['imageScanStatus']['status']

                # After the scan is complete or changed from IN_PROGRESS
                if status == "COMPLETE":
                    print(f"{updated_image['repositoryName']}/{updated_image['imageTags'][0]}: {status}")
                else:
                    print(f"Error {updated_image['repositoryName']}/{status}")
