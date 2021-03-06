FROM tomcat:9-jdk11

LABEL maintainer="Heitor Carneiro <heitor.carneiro@geoambiente.com.br>"

ENV GEOSERVER_VERSION 2.18.0
ENV GEOSERVER_DATA_DIR /var/local/geoserver
ENV GEOSERVER_INSTALL_DIR /usr/local/geoserver
ENV GEOSERVER_EXT_DIR /var/local/geoserver-exts

# Uncomment to use APT cache (requires apt-cacher-ng on host)
#RUN echo "Acquire::http { Proxy \"http://`/sbin/ip route|awk '/default/ { print $3 }'`:3142\"; };" > /etc/apt/apt.conf.d/71-apt-cacher-ng

# Microsoft fonts
RUN echo "deb http://httpredir.debian.org/debian stretch contrib" >> /etc/apt/sources.list
RUN set -x \
	&& apt-get update \
	&& apt-get install -yq ttf-mscorefonts-installer \
	&& rm -rf /var/lib/apt/lists/*

# GeoServer
ADD conf/geoserver.xml /usr/local/tomcat/conf/Catalina/localhost/geoserver.xml

RUN mkdir ${GEOSERVER_DATA_DIR} && mkdir ${GEOSERVER_INSTALL_DIR}
ADD build/geoserver-${GEOSERVER_VERSION}-war.zip ${GEOSERVER_INSTALL_DIR}/

RUN cd ${GEOSERVER_INSTALL_DIR} \
	&& unzip geoserver-${GEOSERVER_VERSION}-war.zip \
	&& unzip geoserver.war \
	&& mv data/* ${GEOSERVER_DATA_DIR} \
	&& rm -rf geoserver-${GEOSERVER_VERSION}-war.zip geoserver.war target *.txt

# Extensions
RUN mkdir ${GEOSERVER_EXT_DIR}
ADD geoserver-exts/* ${GEOSERVER_EXT_DIR}/
ADD conf/controlflow.properties ${GEOSERVER_DATA_DIR}/controlflow.properties

# Community Modules
ADD geoserver-community-modules/* ${GEOSERVER_EXT_DIR}/

RUN echo "[LOG] Extensions added:"
RUN ls ${GEOSERVER_EXT_DIR}

# Enable CORS
RUN sed -i '\:</web-app>:i\
<filter>\n\
    <filter-name>CorsFilter</filter-name>\n\
    <filter-class>org.apache.catalina.filters.CorsFilter</filter-class>\n\
    <init-param>\n\
        <param-name>cors.allowed.origins</param-name>\n\
        <param-value>*</param-value>\n\
    </init-param>\n\
    <init-param>\n\
        <param-name>cors.allowed.methods</param-name>\n\
        <param-value>GET,POST,HEAD,OPTIONS,PUT</param-value>\n\
    </init-param>\n\
</filter>\n\
<filter-mapping>\n\
    <filter-name>CorsFilter</filter-name>\n\
    <url-pattern>/*</url-pattern>\n\
</filter-mapping>' ${GEOSERVER_INSTALL_DIR}/WEB-INF/web.xml

# Tomcat environment
# https://docs.boundlessgeo.com/suite/latest/sysadmin/production/reliability.html
ADD conf/server.xml /usr/local/tomcat/conf/server.xml

# Create tomcat user to avoid root access.
RUN addgroup --gid 1099 tomcat && useradd -m -u 1099 -g tomcat tomcat \
    && chown -R tomcat:tomcat . \
    && chown -R tomcat:tomcat ${GEOSERVER_DATA_DIR} \
    && chown -R tomcat:tomcat ${GEOSERVER_INSTALL_DIR}

# JVM
# *-java11-hotspot: -Xms128M -Xmx756M
# *-java11-hotspot-readonly: -Xms128M -Xmx756M -DGEOSERVER_CONSOLE_DISABLED=true
# *-java11-hotspot-primary: -Xms768M -Xmx2048M
# *-java11-hotspot-secondary: -Xms2G -Xmx3G -DGEOSERVER_CONSOLE_DISABLED=true -DGWC_DISKQUOTA_DISABLED=true -DGWC_METASTORE_DISABLED=true
ENV GEOSERVER_OPTS "-server -Djava.awt.headless=true \
 -Xms128M -Xmx756M \
 -XX:SoftRefLRUPolicyMSPerMB=36000 -XX:+UseParallelGC \
 -XX:PerfDataSamplingInterval=500 -XX:NewRatio=2 \
 -XX:-UseContainerSupport -XX:InitialRAMPercentage=50 -XX:MaxRAMPercentage=70 \
 -Dorg.geotools.referencing.forceXY=true -Dfile.encoding=UTF8 -Duser.timezone=GMT -Djavax.servlet.request.encoding=UTF-8 -Djavax.servlet.response.encoding=UTF-8 -Duser.timezone=GMT -Dorg.geotools.shapefile.datetime=true \
 -DGEOSERVER_DATA_DIR=${GEOSERVER_DATA_DIR}"

ENV JAVA_OPTS "$JAVA_OPTS $GEOSERVER_OPTS"
RUN echo "[LOG] JAVA_OPTS=$JAVA_OPTS"

EXPOSE 8080
ADD start.sh /usr/local/bin/start.sh

# HEALTHCHECK CMD curl --fail http://localhost:8080/geoserver/tiger/ows?service=WFS&version=1.0.0&request=GetFeature&typeName=tiger%3Apoi&maxFeatures=50&outputFormat=application%2Fjson || exit 1
ENTRYPOINT ["/usr/local/bin/start.sh"]
