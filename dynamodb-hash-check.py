import json
import boto3
import time
import os
from boto3.dynamodb.conditions import Key

# 初始化 AWS 客户端
s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table('dynamodb-table-name')  # TODO: 替换为你的 DynamoDB 表名

# S3 中存储 client_id 列表的 Bucket 名称和 Key 路径
bucket_name = 'bucket-name'  # TODO: 替换为你的 S3 Bucket 名称
s3_key = 's3-key.json'       # TODO: 替换为你的 S3 Key 路径

# 多个 hashstr，采用竖排方式书写，便于阅读维护
target_hash_list = [
    '1234567890abcdef1234567890abcdef',
    'abcdef1234567890abcdef1234567890',
    '7890abcdef1234567890abcdef123456'
]

# 从环境变量读取“有效天数”，默认 2 天（单位：毫秒）
expiry_days = int(os.getenv('EXPIRY_DAYS', '2'))
expiry_milliseconds = expiry_days * 86400 * 1000  # 86400 秒 × 1000 = 1 天的毫秒数

def lambda_handler(event, context):
    try:
        # Step 1: 从 S3 读取 client_id 列表（JSON 数组）
        response = s3_client.get_object(Bucket=bucket_name, Key=s3_key)
        client_ids = json.loads(response['Body'].read().decode('utf-8'))
        print(f"已加载 client_id 列表: {client_ids}")

        # Step 2: 读取环境变量 TARGET_INFO_TYPES，支持多个 info_type，逗号分隔，默认 'love'
        target_info_types_str = os.getenv('TARGET_INFO_TYPES')
        if target_info_types_str:
            target_info_types = [s.strip() for s in target_info_types_str.split(',')]
        else:
            target_info_types = ['love']

        now = int(time.time() * 1000)  # 当前时间戳（单位：毫秒）

        # Step 3: 遍历每个 client_id 和每个 info_type，处理 DynamoDB 记录
        for client_id in client_ids:
            for target_info_type in target_info_types:
                # 查询 DynamoDB 中该 client_id + info_type 的所有历史记录
                query_response = table.query(
                    IndexName='client_id-info_type_index',
                    KeyConditionExpression=Key('client_id').eq(client_id) & Key('info_type').eq(target_info_type)
                )
                items = query_response.get('Items', [])
                print(f"client_id={client_id}, info_type={target_info_type} 的历史记录数: {len(items)}")

                # 构建已存在 hashstr → item 的映射，只包含关注的 hashstr
                existing_map = {
                    item['hashstr']: item
                    for item in items
                    if item.get('hashstr') in target_hash_list
                }

                # 决定使用的 ID：如果已有记录则复用其 ID，否则生成新 ID
                if existing_map:
                    new_id = int(next(iter(existing_map.values()))['id'])
                else:
                    max_id = max([int(item['id']) for item in items], default=0)
                    new_id = max_id + 1
                print(f"client_id={client_id}, info_type={target_info_type} 使用 ID: {new_id}")

                # Step 4: 遍历每个 hashstr，根据更新时间和存在情况决定是否写入
                for h in target_hash_list:
                    existing_item = existing_map.get(h)

                    if existing_item:
                        last_ts = int(existing_item.get('timestamp', 0))
                        age_millis = now - last_ts

                        if age_millis < expiry_milliseconds:
                            print(f"⏩ hashstr={h} 在 {age_millis} 毫秒前已更新，跳过写入。")
                            continue
                        else:
                            print(f"✅ hashstr={h} 超过 {expiry_days} 天未更新，将覆盖。")
                    else:
                        print(f"🆕 hashstr={h} 不存在，将新建记录。")

                    # 准备写入的 DynamoDB item，使用毫秒级 timestamp
                    item = {
                        'client_id': client_id,
                        'timestamp': now,
                        'hashstr': h,
                        'id': str(new_id),
                        'info_type': target_info_type,
                        'msg1': "abcdefghijklmn"
                    }

                    # 写入 DynamoDB，put_item 操作存在则覆盖，不存在则插入
                    table.put_item(Item=item)
                    print(f"✅ 已写入记录: {item}")

        return {
            'statusCode': 200,
            'body': json.dumps(
                f"成功处理 {len(client_ids)} 个 client，每个包含 {len(target_info_types)} 个 info_type，每个 info_type 最多 {len(target_hash_list)} 个 hashstr。"
            )
        }

    except Exception as e:
        print(f"❌ 错误发生: {e}")
        return {
            'statusCode': 500,
            'body': json.dumps(f"执行异常: {str(e)}")
        }
