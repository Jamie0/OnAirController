module OAC
	class Controller

		include OAC::Helper::Dispatch

		def initialize config

			@config = config
			@clients = {}
			@networks = {}
			@factory = ServerFactory.new self

			@ips = {}

			@config.get("networks").each do | settings |

				network = OAC::Network.new(settings)
				id = settings["name"]
				@networks[id] = network
				listen_to network

			end

			@config.get("studios").each do | studio |
				
				id = studio["name"]
				@clients[id] = OAC::Client::Disconnected

				[studio["ip"]].flatten.each do | ip |
					raise OAC::Error::ConfigError, "Playout systems sharing IP" if !@ips[id].nil?
					@ips[ip] = id
				end

			end

			@config.get("controllers").each do | controller |

				type = Object.const_get(controller["type"])::Server
				server = @factory.create_server(type, controller["port"], controller["host"])

				# Some interfaces only support one network each
				server.network = @networks[controller["network"]] if controller["network"]

			end

		end

		# Returns a list of networks we've taken control of
		def on_take_control_request event, networks = [], force, client

			networks = [networks] if networks.is_a? OAC::Network
			networks.select do | network |
				next false unless network.should_take_control(client, force)
				network.take_control client
				true
			end

		end

		def on_release_control_request event, networks = [], force, client

			networks = [networks] if networks.is_a? OAC::Network

			# Return the networks as an array
			networks = @networks.map { | a, b | b } if networks == nil

			networks.select do | network |
				next false unless network.should_release_control(client, force)
				network.release_control client
				true
			end

		end

		# Bubble control events up
		def on_control_event *args
			dispatch *args
		end

		def on_disconnect event, client
			@clients[client.id] = OAC::Client::Disconnected
		end

		def register_network network 
			register network
			@networks << network
		end

		def register_client client

			port, ip = Socket.unpack_sockaddr_in(client.socket.getpeername)

			id = id_to_ip ip
			return client.disconnect if id == nil
			client.id = id

			client.on_open
			listen_to client

			old_client = @clients[client.id]

			# Clean up the previous person with this client slot
			if old_client != OAC::Client::Disconnected
				old_client.networks.each { | n | n.take_control client }
			end
			old_client.disconnect

			@clients[client.id] = client

		end

		def run!
			@factory.run!
		end

		private
		def listen_to object

			raise "Object must use OAC::Helper::Dispatch" unless object.class.method_defined? "add_listener"

			object.add_listener OAC::Client::Disconnect, &method(:on_disconnect)
			object.add_listener OAC::Client::TakeControlRequest, &method(:on_take_control_request)
			object.add_listener OAC::Client::ReleaseControlRequest, &method(:on_release_control_request)

			object.add_listener OAC::Event::ControlEvent, &method(:on_control_event)

		end

		def id_to_ip ip

			# We only support one IP per playout system. Splits are out of our scope currently
			@ips[ip]

		end


	end
end