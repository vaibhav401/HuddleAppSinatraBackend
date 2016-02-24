require 'sinatra'

class HuddleApp < Sinatra::Base
	configure { set :server, :puma }

	configure :production, :development do
     enable :logging
   end

	get '/' do
		logger.info "serving request "
		return "hello world" 
	end
end

if __FILE__ == $0
	HuddleApp.run!
end
