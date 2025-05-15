import json
import boto3
import os
from datetime import datetime, timedelta
from boto3.dynamodb.conditions import Key

s3_client = boto3.client('s3')
dynamodb = boto3.resource('dynamodb')
table = dynamodb.Table(os.environ['DDB_TABLE_NAME'])

def lambda_handler(event, context):
    # 读取 S3 上 client_ids 列表
    bucket_name = os.environ['S3_BUCKET']
    s3_key = os.environ['S3_KEY']
    
    response = s3_client.get_object(Bucket=bucket_name, Key=s3_key)
    client_ids = json.loads(response['Body'].read().decode('utf-8'))['client_ids']

    # 从环境变量读取多个 hashstr
    hashstr_list = os.environ.get('HASHSTR_LIST', '')
    valid_hashes = [h.strip() for h in hashstr_list.split(',') if h.strip()]

    # 计算“前天 00:00 UTC”的秒级时间戳
    now = datetime.utcnow()
    two_days_ago = (now - timedelta(days=2)).replace(hour=0, minute=0, second=0, microsecond=0)
    two_days_ago_ts = int(two_days_ago.timestamp())

    target_info_type = 'letter'

    for client_id in client_ids:
        # 查 DynamoDB 的 GSI
        query_response = table.query(
            IndexName='client_id-info_type_index',
            KeyConditionExpression=Key('client_id').eq(client_id) & Key('info_type').eq(target_info_type)
        )

        # 查找是否已有 hashstr 匹配的项
        existing_item = next(
            (item for item in query_response.get('Items', [])
             if item.get('hashstr') in valid_hashes),
            None
        )

        if existing_item:
            last_updated = int(existing_item.get('timestamp', 0))

            # 如果是毫秒，转为秒
            if last_updated > 1e12:
                last_updated = last_updated // 1000

            if last_updated >= two_days_ago_ts:
                print(f"[SKIP] client_id {client_id}: hash matched & updated within 2 days (timestamp={last_updated})")
                continue
            else:
                print(f"[WRITE] client_id {client_id}: hash matched but outdated (timestamp={last_updated})")
                new_id = int(existing_item['id'])
        else:
            if query_response.get('Items'):
                max_item = max(query_response['Items'], key=lambda x: int(x['id']))
                max_id = int(max_item['id'])
            else:
                max_id = 1
            new_id = max_id + 1
            print(f"[WRITE] client_id {client_id}: no matching hash, assigning new ID {new_id}")

        # 统一使用当前 UTC 秒级时间戳
        timestamp_sec = int(datetime.utcnow().timestamp())

        # 构造要写入的项
        item = {
            'client_id': client_id,
            'timestamp': timestamp_sec,
            'hashstr': valid_hashes[0],  # 使用第一个 hash，也可扩展
            'id': new_id,
            'info_type': target_info_type,
            'msg1': '音楽に合わせてA/B/Cボタンを押してダンスしてスコアをゲットしよう！',
            'msg2': 'Follow the music and press A/B/C to dance and score!',
            'msg3': 'Suis la musique et appuie sur A/B/C pour danser et marquer des points !',
            'msg4': 'Folge der Musik und drücke A/B/C, um zu tanzen und Punkte zu sammeln!',
            'msg5': '¡Sigue la música y presiona A/B/C para bailar y ganar puntos!'
        }

        # 实际写入 DynamoDB（取消注释以启用）
        # table.put_item(Item=item)

        print(f"[PREPARED] item ready for write: {item}")
