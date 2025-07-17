#!/bin/bash
SCRIPT_PATH=$(realpath  $0)
SCRIPT_DIR=$(dirname  $SCRIPT_PATH)
source $SCRIPT_DIR/env.sh

QUEUE="queue max-size-buffers=2 max-size-bytes=0 max-size-time=0"

if (($USE_SCREAM == 1)); then
    SCREAMRX0="! screamrx name=screamrx0 screamrx0.src "
    SCREAMRX0_RTCP="screamrx0.rtcp_src ! f0."
else
    SCREAMRX0=""
    SCREAMRX0_RTCP=""
fi

# Second stream is always standard RTP (no SCReAM)
SCREAMRX1=""
SCREAMRX1_RTCP=""

# Define second stream ports (should match sender script)
PORT1_RTP=${PORT1_RTP:-30114}
PORT1_RTCP=${PORT1_RTCP:-30115}

DECODER=avdec_h${ENC_ID}
#DECODER=nvh${ENC_ID}dec

VIDEOSINK0="videoconvert ! fpsdisplaysink video-sink=\"ximagesink\" name=display0"
VIDEOSINK1="videoconvert ! fpsdisplaysink video-sink=\"ximagesink\" name=display1"

# Sink video to V4L2 devices (For use with OBS or similar)
# You will need to install v4l2loopback-dkms and v4l2loopback-utils
# Load the kernel module with:
# sudo modprobe v4l2loopback devices=2 video_nr=10,11 card_label="ScreamCam","RTPCam" exclusive_caps=1

# VIDEOSINK0="videoconvert ! v4l2sink device=/dev/video10 sync=false"
# VIDEOSINK1="videoconvert ! v4l2sink device=/dev/video11 sync=false"

#VIDEOSINK0="fakesink"
#VIDEOSINK1="fakesink"

echo "DEBUG: VIDEOSINK0=$VIDEOSINK0"
echo "DEBUG: VIDEOSINK1=$VIDEOSINK1"
echo "DEBUG: PORT1_RTP=$PORT1_RTP"
echo "DEBUG: PORT1_RTCP=$PORT1_RTCP"

export RECVPIPELINE="rtpbin latency=10 name=r \
udpsrc port=$PORT0_RTP address=$RECEIVER_IP $RETRIEVE_ECN ! \
 queue $SCREAMRX0 ! application/x-rtp, media=video, encoding-name=H${ENC_ID}, clock-rate=90000 ! r.recv_rtp_sink_0 \
 r.send_rtcp_src_0 ! funnel name=f0 ! queue ! udpsink host=$SENDER_IP port=$PORT0_RTCP sync=false async=false \
 $SCREAMRX0_RTCP \
 udpsrc port=$PORT0_RTCP ! r.recv_rtcp_sink_0 \
 r. ! rtph${ENC_ID}depay ! h${ENC_ID}parse ! $DECODER name=videodecoder0 ! $QUEUE ! $VIDEOSINK0
 "

export RECVPIPELINE1="rtpbin latency=10 name=r \
 udpsrc port=$PORT1_RTP address=$RECEIVER_IP ! \
 queue ! application/x-rtp, media=video, encoding-name=H${ENC_ID}, clock-rate=90000 ! r.recv_rtp_sink_1 \
 r.send_rtcp_src_1 ! queue ! udpsink host=$SENDER_IP port=$PORT1_RTCP sync=false async=false \
 udpsrc port=$PORT1_RTCP ! r.recv_rtcp_sink_1 \
 r. ! rtph${ENC_ID}depay ! h${ENC_ID}parse ! $DECODER name=videodecoder1 ! $QUEUE ! $VIDEOSINK1 \
"

killall -9 gst-launch-1.0
echo "DEBUG: RECVPIPELINE1=$RECVPIPELINE1"
gst-launch-1.0 -v $RECVPIPELINE1 &
export GST_DEBUG="screamrx:2"
killall -9 scream_receiver
$SCREAM_TARGET_DIR/scream_receiver