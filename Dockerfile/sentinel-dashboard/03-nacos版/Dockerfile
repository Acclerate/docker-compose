FROM openjdk:8-jre-alpine

MAINTAINER your-name

# 解决时差8小时问题
ENV TZ=Asia/Shanghai
RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# 设置环境变量-运行时也可传参进来耍哈
ENV SENTINEL_AUTH_USERNAME sentinel
ENV SENTINEL_AUTH_PASSWORD sentinel
ENV NACOS_SERVER_ADDR 127.0.0.1:8848
ENV NACOS_NAMESPACE dev
ENV NACOS_GROUP sentinel-group
ENV NACOS_USERNAME nacos
ENV NACOS_PASSWORD nacos

# 添加jar包到容器中
ADD sentinel-dashboard.jar /app.jar

# 对外暴漏的端口号
EXPOSE 8858

# 运行🏃🏃🏃
CMD echo "****** start run ... " & \
    java -Djava.security.egd=file:/dev/./urandom \
    -Dauth.username=${SENTINEL_AUTH_USERNAME} -Dauth.password=${SENTINEL_AUTH_PASSWORD} \
    -Dnacos.server-addr=${NACOS_SERVER_ADDR} -Dnacos.namespace=${NACOS_NAMESPACE} -Dnacos.group=${NACOS_GROUP} \
    -Dnacos.username=${NACOS_USERNAME} -Dnacos.password=${NACOS_PASSWORD} \
    -Dserver.port=8858 -Dcsp.sentinel.api.port=8719 -Dcsp.sentinel.dashboard.server=localhost:8858 -Dproject.name=sentinel-dashboard -jar /app.jar
