# Bamboo

A modern implementation of websocket server equipped with Ruby fiber scheduler.

## Ruby 3 Fiber Scheduler

Since Ruby 3.0, the `Fiber::SchedulerInterface` has been made available to manage and schedule non-blocking fibers. In an I/O intensive application like a websocket server, the "thread and fiber" conbination can potentially be very powerful and efficient.

Bamboo is a websocket server that honors this combination and attempts to achieve better performance. The server is composed of a `greeter` thread and multiple `worker` threads, in which fibers are created for each socket read and writes. The bundled fiber scheduler implemented with `IO::select` then manage the fibers and decide the precedence of handling the I/Os.

## Integrating the server

The server can be integrated into any Ruby applications easily. A quick example of how to start a server is as follows.

```ruby
server = BambooSocket::Server.new
server.start
```

And the server will be started on `ws://127.0.0.1:5613` responding to any pings with pong frames.

## Server

The Bamboo server use callbacks to allow customization of its behaviour duing initialization. Currently available callbacks are `:add`, `:frame`, `:message` and `:remove`.

- `Server::on(:add) { |guest| }`: block is called when a new guest connects.
- `Server::on(:frame) { |guest, payload, type| }`: block is called every time a frame is received.
- `Server::on(:message) { |guest, message, type| }`: block is called when a full message is received.
- `Server::on(:remove) { |guest| }`: block is called when a guest connection is closed.

An example server customized with the callbacks is as follows.

```ruby
server = BambooSocket::Server.new
server.on(:add) do |_guest|
  puts 'New guest connected'
end
server.on(:message) do |guest, msg, type|
  guest.send_message('PONG') if type == :text && msg == 'PING'
  server.guest_list.each { |g| g.send_message(msg) if g != guest } if type == :text
end
server.on(:remove) do |_guest|
  puts 'Guest disconnected'
end
server.start
```

## Guests

Guests are the abstractions of the connecting clients. Whenever a client connects, a new guest instance is created and available via the `:add` callback.

The server itself keeps a `Set` of guest instances in `Server::guest_list`.

A message can be sent to the guest using `Guest::send_message` directly. But Bamboo do not implement any pub/sub, or broadcast systems itself. So if you want to achieve that, you will have to build the broadcast channel system yourself.

```ruby
require 'set'

server = BambooSocket::Server.new
rooms = [Set.new, Set.new, Set.new]
server.on(:add) do |guest|
  room = rooms.sample
  guest.tags.room = rooms.index(room)
  room << guest
end
server.on(:message) do |guest, msg, type|
  guest.send_message('PONG') if type == :text && msg == 'PING'
  rooms[guest.tags.room].each { |g| g.send_message(msg) if g != guest } if type == :text
end
server.on(:remove) do |guest|
  rooms[guest.tags.room].delete(guest)
end
server.start
```

This server example shows how to host guests in rooms and broadcast messages within each room.
