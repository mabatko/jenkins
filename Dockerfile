FROM centos:7
LABEL maintainer="martin.batora@dxc.com"

USER root

RUN groupadd -g ${JENKINS_GID:-1002} jenkins
RUN useradd -m -u ${JENKINS_UID:-1002} -g jenkins jenkins 

ADD requirements.txt .

RUN yum -y update && \
        curl "https://bootstrap.pypa.io/get-pip.py" -o "get-pip.py" && \
        yum -y install \
        python \
        groff \
        less \
        mailcap \
        git \
        openssh-clients \
        bind-utils \
        && \
    python get-pip.py && \
    pip install -r requirements.txt && \
    rm -rf /var/cache/yum/*

WORKDIR /build

USER jenkins
