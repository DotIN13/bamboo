require 'faye/websocket'

count = 1

50.times.map do
  Thread.new do
    EM.run do
      ws = Faye::WebSocket::Client.new('ws://127.0.0.1:5613')

      ws.on :open do |_event|
        p [:open]
        ws.send('Hello, world!')
      end

      ws.on :message do |event|
        count += 1
        p [:message, event.data, count]
      end

      ws.on :close do |event|
        p [:close, event.code, event.reason]
        ws = nil
      end
    end
  end
end.each(&:join)
