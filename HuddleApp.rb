require 'sinatra'
require "sinatra/json"
require "json" # to parse json data 
require 'pry'
require 'google-id-token'

load './Models.rb'

class HuddleApp < Sinatra::Base
	configure { set :server, :puma } # set puma as default server 

	configure :production, :development do
     enable :logging
   end


    before '/*' do 
    	if ["POST", "PATCH"].index request.request_method 
    		# only check for json is request is post or patch
			request.body.rewind
			begin 
		  		@request_payload = JSON.parse request.body.read
		  	rescue  # catch StandardError
		  		halt 401, "send json data"
		  	end
		  	logger.info @request_payload
		end
	end
	before '/team*' do 
		token = env["HTTP_HTTP_X_AUTH_TOKEN"]
		if token.nil?
			halt 404, "Not allowed"
		end
		session = Session.first(:server_token => token)
		if session.nil?
			halt 404, "Not allowed"
		end
		@user = session.user
	end
	before '/user*' do 
		if request.request_method != "POST"
			token = env["HTTP_HTTP_X_AUTH_TOKEN"]
			if token.nil?
				halt 404, "Not allowed"
			end
			session = Session.first(:server_token => token)
			if session.nil?
				halt 404, "Not allowed"
			end
			@user = session.user
		end
	end
	before '/team/*' do
		@team = @user.team
	end

	get '/' do
		logger.info "serving request "
		return "hello world" 
	end

	get '/user' do 
		json @user
	end

	post '/user' do
		# verify token used for identification is valid
		# http://android-developers.blogspot.in/2013/01/verifying-back-end-calls-from-android.html
		# https://github.com/google/google-id-token checkout this gem
		# provide organization to user 
		verify_user_create_json!
		auth_result = verify_google_auth_token( @request_payload["google_auth_token"])
		# user auth result to verify details
		user = User.first(:email => @request_payload["email"]) # check if user with that mail already exists 
		if user.nil? 
			logger.info "Creating new User"
			user = User.from_hash @request_payload
			session = Session.new(:server_token => generate_server_token(user.username, user.email))
			if not user.save
				halt 401, "Insufficient arguments for user creation"
			end
			session.user = user
			session.save
			logger.info "user created successfully"
		else
			logger.info "User already exists"
			session = user.session
			if session.nil?
				session = Session.new(:server_token => generate_server_token(user.username, user.email))
				session.user = user
				session.save
			end
		end
		json user.to_hash
	end


	patch '/user/:id' do
		verify_user_update_json!
		user = User.get(params[:id])
		if @user != user
			halt 401, "Not allowed"
		end
		#verify wheter user which is getting patched is same as logged in user 
		if user.nil? or 
			halt 401, "user not found"
		end
		user.update_from_hash(@request_payload)
		if not user.save
			halt 401, "Insufficient user data"
		end
		json user.to_hash
	end

	get '/teams' do 
		teams = Team.all(:organization => @user.organization)
		json teams
	end

	get '/team/user' do
		# get members from team of users
		team = Team.first(:id => params[:id])
		if team.nil? 
			halt 404, "Illegal arguments"
		end
		updated_after = @request_payload["updated_after"].nil? ? 0 : @request_payload["updated_after"].nil?
		json @team.members.collect {|task| task.updated_at >= updated_after}
	end

	patch '/team/:id/user' do 
		team = Team.first(:id => params[:id])
		if team.nil? 
			halt 404, "Illegal arguments"
		end
		if @request_payload["is_scrum_master"]
			@user.is_scrum_master = true
		end
		@user.team = team
		@user.save
		json team
	end

	delete '/team/:id/user' do
		if @team.nil?
			halt 404, "Not found"
		end
		user.team = nil
		user.save
	end

	get '/team/:id/tasks' do 
		updated_after = @request_payload["updated_after"].nil? ? 0 : @request_payload["updated_after"].nil?
		json @team.tasks.collect {|task| task.updated_at >= updated_after}
	end

	post '/team/:id/tasks' do 
		verify_task_json!
		task = Task.from_hash @request_payload
		if not @request_payload["is_open"]
			task.user = @user 
		end
		task.team = @team
		if not task.save 
			halt 401, "Illegal arguments"
		end
		json task
	end

	patch '/team/:id/task/:id' do 
		verify_task_json!
		task = Task.first(:id => params["id"])
		if task.nil?
			halt 404, "Task Not found"
		end
		task.update_from_hash @request_payload
		if not task.save 
			halt 401, "Illegal arguments"
		end
		json task
	end

	patch '/team/:id/task/:id/own_task' do 
		task = Task.first(:id => params["id"])
		if task.nil? or not task.user.nil?
			halt 404, "Task Not found"
		end
		task.user = @user
		if not task.save 
			halt 401, "Illegal arguments"
		end
	end

	patch '/team/:id/task/:id/discuss_task' do 
		task = Task.first(:is => params["id"])
		if task.nil? or not task.user.nil?
			halt 404, "Task Not found"
		end
		task.users_for_discussion += @user.username
		if not task.save 
			halt 401, "Illegal arguments"
		end
	end


	def verify_user_create_json! 
		result = true
		result = @request_payload["username"].nil? ? false : result 
		result = @request_payload["email"].nil?  ? false : result 
		# result = @request_payload["password"].nil?  not required as user signs in from google
		result = @request_payload["full_name"].nil?  ? false : result 
		result = @request_payload["is_scrum_master"].nil?  ? false : result 
		result = @request_payload["gcm_token"].nil?  ? false : result 
		result = @request_payload["organization"].nil?  ? false : result 
		result = @request_payload["google_auth_token"].nil?  ? false : result 
		if result == false
			halt 401, "Insufficient arguments"
			logger.info "User provided Insufficient data for user creation"
		end
	end
	def verify_user_update_json! 
		result = true
		result = @request_payload["username"].nil?  ? false : result 
		result = @request_payload["email"].nil?  ? false : result 
		result = @request_payload["full_name"].nil?  ? false : result 
		result = @request_payload["is_scrum_master"].nil?  ? false : result 
		if result == false
			halt 401, "Insufficient arguments"
			logger.info "User provided Insufficient data for user creation"
		end
	end
	def verify_task_json! 
		result = true
		result = @request_payload["title"].nil? ? false : result 
		result = @request_payload["detail"].nil? ? false : result 
		result = @request_payload["is_complete"].nil?  ? false : result 
		result = @request_payload["is_open"].nil?  ? false : result 
		# result = @request_payload["password"].nil?  not required as user signs in from google
		result = @request_payload["discuss_task"].nil?  ? false : result 
		result = @request_payload["users_for_discussion"].nil?  ? false : result 
		result = @request_payload["complete_on"].nil?  ? false : result 
		result = @request_payload["sync_code"].nil?  ? false : result 
		if result == false
			halt 401, "Insufficient arguments"
			logger.info "User provided Insufficient data for user creation"
		end
	end

	def verify_google_auth_token(google_auth_token)
		validator = GoogleIDToken::Validator.new
		jwt = validator.check(token, GOOGLE_AUTH_ID)
		if jwt
			jwt
		else
  			halt 404, "Illegal User !! go away"
		end
	end

	def generate_server_token(username, full_name)
		Digest::SHA256.hexdigest (username + full_name) # add salt here 
	end
end

if __FILE__ == $0
	HuddleApp.run!
end
