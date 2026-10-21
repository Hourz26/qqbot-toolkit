#!/bin/bash
# AstrBot extra python deps that live only in the container layer.
# Container-layer pip installs are lost on `docker compose up --force-recreate`
# or an image upgrade, so re-run this after any container recreation.
set -e
docker exec astrbot pip install --no-cache-dir \
  -i https://mirrors.aliyun.com/pypi/simple/ --trusted-host mirrors.aliyun.com \
  'chinese-calendar>=1.9.2' 'lunarcalendar>=0.0.9' boto3 tqdm \
  'markdown>=3.4' 'imgkit>=1.2' 'segno>=1.5' 'imageio-ffmpeg>=0.4'
echo "extra deps OK"
