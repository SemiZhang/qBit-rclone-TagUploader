# qBit-rclone-TagUploader
将qbittorrent下载完成的文件，通过rclone上传到网盘

## 依赖：
[jq](https://stedolan.github.io/jq/)

## 使用:
1. 配置 rclone 连接到网盘
2. 启用 qbittorrent 的 WebUI
3. 下载 qBit-rclone-TagUploader.sh 到本地，并修改 qb_username，qb_password，qb_web_url 为自己的 WebUI 的登录名，密码和 URL 链接。
4. 修改 unfinished_tag 为将在 qbittorent 中使用的 Tag。（只有被添加了相应 Tag 的已完成任务会被执行上传）
5. 修改 rclone_dest 为 rclone 配置中的网盘路径（以英文冒号结尾的配置名）。unfinished_tag 和 rclone_dest 以数组中的排序对应。
6. 在 qbittorrent 为需要上传的任务添加 Tag。
7. 将 qBit-rclone-TagUploader.sh 添加到计划任务中，例如 crontab。

## 疑难：
**1. Log中显示上传成功，但实际并没有，并且用时仅为不到10秒**

由于 rclone 始终以 exit 1 结束进程，因此难以判断实际上传情况。 请排查以下问题：

- 检查 rclone 与目标网盘是否能够正确建立连接（使用 rclone lsd 查看网盘目录，无报错则没问题）
- 确保 rclone_dest 中填写了正确的 rclone 配置路径
- 手动运行 qBit-rclone-TagUploader.sh 查看报错信息


**2. 在上传中途异常退出后，任务始终为上传中 / 已完成的任务不开始上传了**

手动运行 qBit-rclone-TagUploader.sh，若报错显示：“已有程序在上传，退出”，执行以下步骤
1. 清除 qbittorrent 中的 “上传中” Tag
2. 删除用户根目录下的 qbup.lock 文件
