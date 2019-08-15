#!/bin/bash
#本脚本的功能为在人工恢复了后端故障服务器后,将其添加进入MHA集群
#app存储mha主配置文件路径
#mhaip为管理服务器ip
#ip存储所有后台服务器ip
	#注意第一次书写ip时要与mha主配置中相对应server1的ip写在第一个
	#默认candidate_master=1,port=3306,如需修改请查找对应位置进行修改
#mhamon为监控用户名
#mhamonpw为监控用户密码
#repluser为数据同步用户名
#repluserpw为数据同步用户密码
app=/etc/mha/app1.cnf
mhaip=(192.168.4.57)
ip=(192.168.4.51 192.168.4.52 192.168.4.53)
mhamon=mhamon
mhamonpw=abcd
repluser=repluser
repluserpw=abcd
#stat为中间量
#num为后台服务器总个数
i=0
while [ -n "${ip[$i]}" ]
do
        stat[$i]=0
        let i++
done
num=$i
#统计正常库ip
tjzckip(){
masterha_check_repl --conf=$app &> 1.txt
zt=`sed -n '$p' 1.txt`
zt=${zt##*Health }
zt=${zt// /}
health='isOK.'
if [ $zt != $health ];then
	echo '健康状态出错' && exit
fi
masterip=`grep '(current master)' 1.txt`
masterip=${masterip%%(*}
slave=`awk '/\+--/' 1.txt`
slave=${slave#*+--}
slaveip=()
i=1
z=`echo $slave | awk '{print $1}'`
while [ ! -z $z ]
do	
	slaveip[$i]=${slave%%(*}
	slave=${slave#*)}
	slave=${slave#*+--}
	z=`echo $slave | awk '{print $1}'`
	let i++
done
rm -rf 1.txt
}
#找出错误ip
zccwip(){
for j in `seq $[i-1]`
do
	csip=${slaveip[$j]}
	for k in `seq $num`
	do
		if [ ${ip[$[k-1]]} == $csip ];then
			let stat[$[k-1]]++
		fi
	done
done
for k in `seq $num`
do
	if [ ${ip[$[k-1]]} == $masterip ];then
		let stat[$[k-1]]++
	fi
done
}
#获取主库日志,mhamon为监控用户,4.txt为临时文件,log存储日志名,pos存储偏移量
hq(){
mysql -h$masterip -u$mhamon -p$mhamonpw -e "show master status" &> 4.txt
file=`awk 'NR==3{print $1}' 4.txt`
pos=`awk 'NR==3{print $2}' 4.txt`
rm -rf 4.txt
}
#在恢复的主机生成主从结构,并在管理节点将其添加进去repluser为数据同步用户
zc(){
for k in `seq $num`
do
	if [ ${stat[$[k-1]]} -eq 0 ];then
		mysql -h${ip[$[k-1]]} -u$mhamon -p$mhamonpw -e "change master to master_host=\"$masterip\",master_user=\"$repluser\",master_password=\"$repluserpw\",master_log_file=\"$file\",master_log_pos=$pos;start slave;"
		echo -e "\n[server$k]\ncandidate_master=1\nhostname=${ip[$[k-1]]}\nport=3306" >> $app
	fi
done
}
main (){
tjzckip
zccwip
hq
zc
}
main
