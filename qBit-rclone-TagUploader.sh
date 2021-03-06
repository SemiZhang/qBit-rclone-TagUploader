#!/bin/sh

qb_version="4.2.1" # 改：qBit的版本号，共三位数字
qb_username="用户名" # 改：qBit WebUI的登录用户名
qb_password="密码" # 改：qBit WebUI的登录密码
qb_web_url="http://localhost:8080" # 改：qBit WebUI的登录地址
log_dir="${HOME}/log/qBit-rclone-TagUploader" # 改：此脚本的日志保存的路径
rclone_dest=("BG:/Upload" "BG2:/") # rclone上传目录；挂载名称参考rclone config中的name字段；格式为"XX:FOLDER"
rclone_parallel="32" # rclone上传线程 默认4

unfinished_tag=("待上传-BG" "待上传-BG2") # 请自行添加此Tag至qBittorrent中
uploading_tag="上传中"
finished_tag="已上传"
noupload_tag="上传失败"


if [ ! -d ${log_dir} ]
then
	mkdir -p ${log_dir}
fi

version=$(echo ${qb_version} | grep -P -o "([0-9]\.){2}[0-9]" | sed s/\\.//g)
startPat=`date +'%Y-%m-%d %H:%M:%S'`  # 时间计算方案
start_seconds=$(date --date="$startPat" +%s);

function qb_login(){
	if [ ${version} -gt 404 ]
	then
		qb_v="1"
		cookie=$(curl -s -i --header "Referer: ${qb_web_url}" --data "username=${qb_username}&password=${qb_password}" "${qb_web_url}/api/v2/auth/login" | grep -P -o 'SID=\S{32}')
		if [ -n ${cookie} ]
		then
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录成功！cookie:${cookie}" 

		else
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录失败！" 
		fi
	elif [[ ${version} -le 404 && ${version} -ge 320 ]]
	then
		qb_v="2"
		cookie=$(curl -s -i --header "Referer: ${qb_web_url}" --data "username=${qb_username}&password=${qb_password}" "${qb_web_url}/login" | grep -P -o 'SID=\S{32}')
		if [ -n ${cookie} ]
		then
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录成功！cookie:${cookie}" 
		else
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] 登录失败" 
		fi
	elif [[ ${version} -ge 310 && ${version} -lt 320 ]]
	then
		qb_v="3"
		echo "qBittorrent版本过旧"
		exit
	else
		qb_v="0"
		echo "qBittorrent版本不存在"
		exit
	fi
}

# 先移除指定tag，后增加自己的tag
function qb_change_hash_tag(){
	file_hash=$1
	fromTag=$2
	toTag=$3
	res_remove="0"
	res_add="0"
	if [ ${qb_v} == "1" ]
	then # 这里是添加某些tag的方法
		trys=0
		until [[ $trys -gt 3 ]]
		do
			res_remove=$(curl -s -w "%{http_code}" -X POST -d "hashes=${file_hash}&tags=${fromTag}" "${qb_web_url}/api/v2/torrents/removeTags" --cookie "${cookie}")
			if [ $res_remove != "200" ]
			then
				qb_login
				res_remove=$(curl -s -w "%{http_code}" -X POST -d "hashes=${file_hash}&tags=${fromTag}" "${qb_web_url}/api/v2/torrents/removeTags" --cookie "${cookie}")
				let trys++
				if [[ ${trys} -gt 3 ]]
				then
					echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag删除失败'${fromTag}' - ${res_remove} - ${file_hash}"
					echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag删除失败'${fromTag}' - ${res_remove} - ${file_hash}" >> ${log_dir}/qb.log
				fi
			else
				break
			fi
		done
		
		trys=0
		until [[ $trys -gt 3 ]]
		do
			res_add=$(curl -s -w "%{http_code}" -X POST -d "hashes=${file_hash}&tags=${toTag}" "${qb_web_url}/api/v2/torrents/addTags" --cookie "${cookie}")
			if [ $res_add != "200" ]
			then
				qb_login
				res_add=$(curl -s -w "%{http_code}" -X POST -d "hashes=${file_hash}&tags=${toTag}" "${qb_web_url}/api/v2/torrents/addTags" --cookie "${cookie}")
				let trys++
				if [[ ${trys} -gt 3 ]]
				then
					echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag添加失败'${toTag}' - ${res_add} - ${file_hash}"
					echo "![$(date '+%Y-%m-%d %H:%M:%S')] Tag添加失败'${toTag}' - ${res_add} - ${file_hash}" >> ${log_dir}/qb.log
				fi
			else
				break
			fi
		done
		
		if [ ${res_remove} == ${res_add} ] && [ ${res_add} == "200" ]
		then
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tag已从'${fromTag}'改为'${toTag}' - ${file_hash}"
			echo "[$(date '+%Y-%m-%d %H:%M:%S')] Tag已从'${fromTag}'改为'${toTag}' - ${file_hash}" >> ${log_dir}/qb.log
		fi
	elif [ ${qb_v} == "2" ]
	then
		curl -s -X POST -d "hashes=${file_hash}&category=${fromTag}" "${qb_web_url}/command/removeCategories" --cookie ${cookie}
		curl -s -X POST -d "hashes=${file_hash}&category=${toTag}" "${qb_web_url}/command/setCategory" --cookie ${cookie}
	else
		echo "qb_v=${qb_v}"
	fi
}

function rclone_copy(){
	torrent_name=$1
	torrent_hash=$2
	torrent_path=$3
	n=$4
	
	echo ${torrent_name}
	echo ${torrent_hash}
	echo ${torrent_path}

	# tag = 待上传
	# 这里执行上传程序
	if [ -f "${torrent_path}" ]
	then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：文件 - ${root_folder}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：文件 - ${root_folder}" >> ${log_dir}/qb.log
		type="file"
	elif [ -d "${torrent_path}" ]
	then
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：目录 - ${root_folder}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 类型：目录 - ${root_folder}" >> ${log_dir}/qb.log
		type="dir"
	else
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未知类型，取消上传 - ${torrent_path}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 未知类型，取消上传 - ${torrent_path}" >> ${log_dir}/qb.log
		# tag = 不上传
		qb_change_hash_tag ${torrent_hash} ${unfinished_tag[n]} ${noupload_tag}
		return
	fi
	# tag = 上传中
	qb_change_hash_tag ${torrent_hash} ${unfinished_tag[n]} ${uploading_tag}
	# 执行上传
	if [ ${type} == "file" ]
	then # 这里是rclone上传的方法
		rclone_copy_cmd=$(rclone -v copy --transfers ${rclone_parallel} "${torrent_path}" ${rclone_dest[n]}/)
	elif [ ${type} == "dir" ]
	then
		root_folder=$(echo $torrent_path | awk -F '/' '{print $NF}')
		rclone_copy_cmd=$(rclone -v copy --transfers ${rclone_parallel} "${torrent_path}"/ ${rclone_dest[n]}/"${root_folder}"/)
	fi

	# tag = 已上传
	qb_change_hash_tag ${torrent_hash} ${uploading_tag} ${finished_tag}

	endPat=`date +'%Y-%m-%d %H:%M:%S'`
	end_seconds=$(date --date="$endPat" +%s);
	use_seconds=$((end_seconds-start_seconds));
	use_min=$((use_seconds/60));
	use_sec=$((use_seconds%60));
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] 上传完成-用时:${use_min}分${use_sec}秒 - ${rclone_dest[n]} - ${root_folder}"
	echo "[$(date '+%Y-%m-%d %H:%M:%S')] 上传完成-用时:${use_min}分${use_sec}秒 - ${rclone_dest[n]} - ${root_folder}" >> ${log_dir}/qb.log
	echo -e >> ${log_dir}/qb.log
}

function file_lock(){
	$(touch qbup.lock)
}
function can_go_lock(){
	lockStatus=$(ls | grep qbup.lock)
	if [ -z "${lockStatus}" ]
	then
		noLock="1"
		return
	fi
	noLock="0"
}
function file_unlock(){
	$(rm -rf qbup.lock)
}

function doUpload(){
	torrentInfo=$1
	i=$2
	n=$3
	
	# IFS保存，因为名字中可能出现多个空格
	OLD_IFS=$IFS
	IFS="\n"
	
	torrent_name=$(echo "${torrentInfo}" | jq ".[$i] | .name" | sed s/\"//g)
	torrent_hash=$(echo "${torrentInfo}" | jq ".[$i] | .hash" | sed s/\"//g)
	torrent_path=$(echo "${torrentInfo}" | jq ".[$i] | .content_path" | sed s/\"//g)
	
	IFS=$OLD_IFS
	

	can_go_lock
	if [[ ${noLock} == "1" ]] # 厕所门能开
	then
		file_lock # 锁上厕所门
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始上传-${torrent_name}"
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 开始上传-${torrent_name}" >> ${log_dir}/qb.log
		rclone_copy "${torrent_name}" "${torrent_hash}" "${torrent_path}" $n
	else
		echo "[$(date '+%Y-%m-%d %H:%M:%S')] 已有程序在上传，退出"
		return # 打不开门，换个时间来
	fi
	file_unlock # 打开厕所门，出去
}

# 每次只查询一条数据，！！上传一条数据！！
function qb_get_status(){
	qb_login
	if [ ${qb_v} == "1" ]
	then
		for ((n=0;n<${#unfinished_tag[@]};n++))
		do
			torrentInfo=$(curl -s "${qb_web_url}/api/v2/torrents/info?filter=completed&tag=${unfinished_tag[n]}" --cookie "${cookie}")
			completed_torrents_num=$(echo ${torrentInfo} | jq 'length')
			echo ${unfinished_tag[n]}":"${rclone_dest[n]}":任务数:"${completed_torrents_num}
			for((i=0;i<${completed_torrents_num};i++));
			do
				curtag=$(echo ${torrentInfo} | jq ".[$i] | .tags" | sed s/\"//g | grep -P -o "${unfinished_tag[n]}")
				if [ -z "${curtag}" ]
				then
					curtag="null"
				fi

				if [ ${curtag} == "${unfinished_tag[n]}" ]
				then
					doUpload "${torrentInfo}" ${i} ${n}
					# 每次只上传一个数据，否则的话，可能会导致多线程的争用问题
					break
				fi
			done
		done
	elif [ ${qb_v} == "2" ]
	then
		torrentInfo=$(curl -s "${qb_web_url}/query/torrents?filter=completed&category=${unfinished_tag}" --cookie "${cookie}")
		completed_torrents_num=$(echo ${torrentInfo} | jq 'length')
		echo "待上传标签任务数："${completed_torrents_num}
		for((i=0;i<${completed_torrents_num};i++));
		do
			curtag=$(echo ${torrentInfo} | jq ".[$i] | .category" | sed s/\"//g)
			if [ -z "${curtag}" ]
			then
				curtag="null"
			fi
			if [ ${curtag} == "${unfinished_tag}" ]
			then
				doUpload "${torrentInfo}" ${i}
				# 每次只上传一个数据，否则的话，可能会导致多线程的争用问题
				break
			fi
		done
	else
		echo "获取错误"
		echo "qb_v=${qb_v}"
	fi
}

qb_get_status