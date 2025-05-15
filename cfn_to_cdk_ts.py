
import os
import json
import yaml
import subprocess
import shutil

INPUT_DIR = "input-templates"
CDK_PROJECTS_DIR = "cdk-projects"
OUTPUT_DIR = "output-zips"

def detect_project(file_path):
    try:
        with open(file_path, 'r') as f:
            if file_path.endswith(".yaml") or file_path.endswith(".yml"):
                content = yaml.safe_load(f)
            else:
                content = json.load(f)
        metadata = content.get("Metadata", {})
        app_name = metadata.get("AppName")
        if not app_name:
            print(f"[警告] 模板 {file_path} 缺少 Metadata.AppName 字段，跳过。")
            return None
        app_path = os.path.join(CDK_PROJECTS_DIR, app_name)
        if os.path.isdir(app_path):
            return app_name
        else:
            print(f"[警告] 找不到匹配的 CDK 项目目录：{app_path}")
            return None
    except Exception as e:
        print(f"[错误] 解析模板失败：{file_path}，原因：{e}")
        return None

def build_cdk_project(app_name):
    project_path = os.path.join(CDK_PROJECTS_DIR, app_name)
    print(f"[信息] 开始构建 CDK 项目：{app_name}")
    try:
        subprocess.run(["npm", "install"], cwd=project_path, check=True)
        subprocess.run(["npx", "cdk", "synth"], cwd=project_path, check=True)
    except subprocess.CalledProcessError as e:
        print(f"[错误] 构建失败：{e}")
        return
    out_dir = os.path.join(project_path, "cdk.out")
    if os.path.exists(out_dir):
        zip_path = os.path.join(OUTPUT_DIR, f"{app_name}.zip")
        shutil.make_archive(zip_path.replace('.zip', ''), 'zip', out_dir)
        print(f"[成功] ZIP 包已生成：{zip_path}")
    else:
        print(f"[警告] 未找到 cdk.out 目录，跳过打包：{app_name}")

def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    if not os.path.exists(INPUT_DIR):
        print(f"[提示] 未找到 {INPUT_DIR} 文件夹，请创建后放入模板")
        return
    for file_name in os.listdir(INPUT_DIR):
        if file_name.endswith((".yaml", ".yml", ".json")):
            file_path = os.path.join(INPUT_DIR, file_name)
            app = detect_project(file_path)
            if app:
                build_cdk_project(app)

if __name__ == "__main__":
    main()
