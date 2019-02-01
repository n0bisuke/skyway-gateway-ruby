require './peer.rb'
require './media.rb'

require "net/http"
require "json"
require "socket"

HOST = "localhost"
PORT = 8000
TARGET_ID = "js"
skyway_api_key = ""

def on_open(peer_id, peer_token)
  (video_id, video_ip, video_port) = create_media(true)

  p_id = ""
  m_id = ""
  th_call = listen_call_event(peer_id, peer_token) {|media_connection_id|
    m_id = media_connection_id
    answer(media_connection_id, video_id)
    # cmd = "gst-launch-1.0 v4l2src device=/dev/video0 ! videoconvert ! video/x-raw,width=640,height=480,format=I420 ! videoconvert ! vp8enc deadline=1  ! rtpvp8pay pt=96 ! udpsink port=#{video_port} host=#{video_ip} sync=false";
    cmd = "gst-launch-1.0 -e rpicamsrc ! video/x-raw,width=640,height=480,framerate=30/1 ! videoconvert ! vp8enc deadline=1  ! rtpvp8pay pt=96 ! udpsink port=#{video_port} host=#{video_ip} sync=false"
    # cmd = "gst-launch-1.0 rpicamsrc preview=0 bitrate=1500000 ! 'video/x-h264, width=1280, height=720, framerate=30/1,profile=high' ! h264parse ! rtph264pay ! udpsink port=#{video_port} host=#{video_ip}"
    p_id = Process.spawn(cmd)
  }

  p "before"
  th_call.join
  p "befor_close"
  th_close = listen_close_event(m_id) {|e|
    p e
    p "はっか"
    Process.kill("KILL", p_id)
    delete_media_connection(m_id)
    close_peer(peer_id, peer_token)
    skyway_api_key = ""
    peer_token = create_peer(skyway_api_key, peer_id)
    on_open(peer_id, peer_token)
  }
  th_close.join
  [m_id, p_id]
end

def delete_media_connection(media_connection_id)
  # params = {
  #     media_connection_id: media_connection_id,
  # }
  p media_connection_id
  res = request(:delete, "/media/connections/#{media_connection_id}")
  if res.is_a?(Net::HTTPNoContent)
    # 正常動作の場合NoContentが帰る
  else
    # 異常動作の場合は終了する
    p res
    exit(1)
  end
  p "close!!!!"
  p res
end

def listen_close_event(media_connection_id, &callback)
  async_get_event("/media/connections/#{media_connection_id}/events", "CLOSE") {|e|
    if callback
      callback.call(e)
    end
  }
end

if __FILE__ == $0
  if ARGV.length != 1
    p "please input peer id"
    exit(0)
  end
  # 自分のPeer IDは実行時引数で受け取っている
  peer_id = ARGV[0]

  # SkyWayのAPI KEYは盗用を避けるためハードコーディングせず環境変数等から取るのがbetter
  skyway_api_key = ""

  # SkyWay WebRTC GatewayにPeer作成の指示を与える
  # 以降、作成したPeer Objectは他のユーザからの誤使用を避けるためtokenを伴って操作する
  peer_token = create_peer(skyway_api_key, peer_id)
  # WebRTC GatewayがSkyWayサーバへ接続し、Peerとして認められると発火する
  # この時点で初めてSkyWay Serverで承認されて正式なpeer_idとなる
  media_connection_id = ""
  process_id = ""
  th_onopen = listen_open_event(peer_id, peer_token) {|peer_id, peer_token|
    (media_connection_id, process_id) = on_open(peer_id, peer_token)
  }

  th_onopen.join

  exit_flag = false
  while !exit_flag
    input = STDIN.readline().chomp!
    exit_flag = input == "exit"
  end

  close_media_connection(media_connection_id)
  close_peer(peer_id, peer_token)
  Process.kill(:TERM, process_id)
end