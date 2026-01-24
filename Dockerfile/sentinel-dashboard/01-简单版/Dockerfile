FROM openjdk:8-jre-alpine

MAINTAINER your-name

# 解决时差8小时问题
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 添加jar包到容器中
ADD sentinel-dashboard-1.8.2.jar /app.jar

# 对外暴漏的端口号
EXPOSE 8858

# 运行🏃🏃🏃
CMD echo "****** start run ... " & \
    java -Djava.security.egd=file:/dev/./urandom -Dserver.port=8858 -Dcsp.sentinel.api.port=8719 -Dcsp.sentinel.dashboard.server=localhost:8858 -Dproject.name=sentinel-dashboard -jar /app.jar
