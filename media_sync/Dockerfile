ARG BUILD_FROM
FROM $BUILD_FROM

RUN apk add --no-cache rsync openssh-client rclone curl

COPY run.sh media-sync.sh /
RUN chmod a+x /run.sh /media-sync.sh

CMD [ "/run.sh" ]
