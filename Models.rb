require 'data_mapper'
require 'dm-core'
require 'dm-types'
require 'dm-validations'
require 'date'
require 'dm-serializer'
load 'keys.secret_file'

DataMapper.setup(:default, "mysql://"+ DB_USERNAME+":"+ DB_PASSWORD+"@localhost/"+ DB_NAME)

class User
	include DataMapper::Resource


	property :id, Serial 
	property :email, String, :length => 5..255
	property :username, String, :length => 5..255
	property :full_name, String, :length => 6..255
	property :password, BCryptHash
	property :image_url, String 	# to get image_ associated with users gmail account
		
	property :gcm_token, String, :length => 5..255 # to store gcm token of client 

		#server only
	property :created_at, DateTime   # handles by datamapper 
	property :updated_at, DateTime   # handles by datamapper
	
	property :is_scrum_master, Boolean, :default => false
	
	
	has n, :tasks 					# for task related to this user
	belongs_to :team , :required => false 				# to accociate a team with a user
	
	# no need for validation as user will be logged in via google sign in so either user 
	# is new then we will create a new user else we will return an existing user 

	after :save do
		if not self.team.nil?
			team = self.team
			team.user_modified_after = self.updated_at.strftime("%s").to_i
			team.save
		end
		true
	end

	after :create do
		if not self.team.nil?
			self.team.user_modified_after = self.updated_at.strftime("%s").to_i
			self.team.save
		end
		true
	end

	def to_hash
		{
			:id => id,
			:email => email,
			:username => username,
			:full_name => full_name,
			:created_at => created_at.strftime("%s").to_i,
			:updated_at => updated_at.strftime("%s").to_i,
			:team_id => team.nil? == true ? -1 : team.id,
			:image_url => image_url,
			:is_scrum_master => is_scrum_master,
			:tasks  => tasks.map {|task| task.to_hash},
			:gcm_token => gcm_token
			
		}
	end
	def to_json(*a)
		self.to_hash.to_json
	end

	def self.from_hash(hash)
		user = User.new
		user.password = hash["password"]
		user.update_from_hash(hash)
		user
	end

	def update_from_hash(hash)
		self.username = hash["username"]
		self.email = hash["email"]
		self.full_name = hash["full_name"]
		self.image_url = hash["image_url"]
		self.is_scrum_master = hash["is_scrum_master"]
		if not hash["reg_token"].nil?
			self.reg_token =hash["reg_token"]
		end
	end

end


class Team
	include DataMapper::Resource

	property :id, Serial
	property :name, String, :length => 5..255
	property :organization, String, :length => 5..255

	property :image_url, String 

		# for server only 
	property :created_at, DateTime   # handles by datamapper
	property :updated_at, DateTime   # handles by datamapper
	
		# to handle mobile data
	property :task_modified_after, Integer, :default => 0
	property :user_modified_after, Integer, :default => 0

	has n, :members, 'User'
	has n, :tasks
	

	def to_hash 
		{
			:id => id,
			:name => name,
			:image_url => image_url,
			:created_at => created_at.strftime("%s").to_i,
			:updated_at => updated_at.strftime("%s").to_i,
			:task_modified_after => task_modified_after,		
			:user_modified_after => user_modified_after,
			:members  => members.map {|member| member.to_hash},
			:tasks  => tasks.first(50).map {|task| task.to_hash},	
		}
	end

	def to_json(*a)
		self.to_hash.to_json
	end

	def self.from_hash(hash)
		team = Team.new
		team.update_from_hash
	end

	def update_from_hash(hash)
		self.name = hash["name"]
		self.pass = hash["pass"]
		self.image_url = hash["image_url"]	
	end


	def users_modified_after (time) # time should be string of epoch
		members.all(:modified_after.gt =>  time)
	end 
	def tasks_modified_after(time) # time should be string 
		tasks.all(:modified_after.gt => time)
	end
end

class Task
	include DataMapper::Resource

	property :id, Serial
	property :title, String , :length => 1..80
	property :detail, String , :length => 0..255, :required => false
	property :is_complete, Boolean, :default => false 

	property :discuss_task, Boolean, :default => false

	property :users_for_discussion, Text, :lazy => :false 

			# for server only 
	property :created_at, DateTime   # handles by datamapper
	property :updated_at, DateTime   # handles by datamapper



	property :complete_on, Integer   # store only data

	# to check if task is already present check that if servr_id is present or not 

	property :sync_code , String, :length => 1..255


	belongs_to :user, :required => false
	belongs_to :team

	after :save do 
		if not self.team.nil?
			team = self.team
			team.task_modified_after = self.updated_at.strftime("%s").to_i
			team.save
		end
		true
	end

	after :create do 
		if not self.team.nil?
			team = self.team
			team.task_modified_after = self.updated_at.strftime("%s").to_i
			team.save
		end
		true
	end

	def to_hash
		{
			:id => id,
			:title => title,
			:detail => detail,
			:is_complete => is_complete,
			:user_id => user.nil? == true ? -1 : user.id,
			:team_id => team.id,
			:created_at => created_at.strftime("%s").to_i,
			:updated_at => updated_at.strftime("%s").to_i,
			:sync_code => sync_code,
			:complete_on => complete_on,
			:discuss_task => discuss_task,
			:users_for_discussion => users_for_discussion

		}
	end
	def to_json(*a)
		self.to_hash.to_json(*a)
	end

	def self.from_hash(hash)
		task  = Task.new
		task.update_from_hash(hash)
		task
	end

	def update_from_hash(hash)
		self.title = hash["title"]
		self.detail = hash["detail"]
		self.is_complete =  hash["is_complete"] 
		self.priority = hash["priority"]
		self.sync_code = hash["sync_code"]
		self.complete_on = hash["complete_on"]
		self.discuss_task = hash["discuss_task"]
		self.users_for_discussion += "," + hash["users_for_discussion"]
	end

end

class Session
	include DataMapper::Resource
	property :id, Serial
	property :server_token, String, :length => 1..255

	belongs_to :user

	def to_json(*a){
		:id => id,
		:server_token => server_token,
		:user => user
		}.to_json(*a)
	end
end

DataMapper.finalize.auto_upgrade!
