load './models.rb'

(1..30).each do |i|
	team = Team.new 
	team.name = "Team #" + i.to_s
	team.organization = "gmail.com"
	team.save
end
user = User.last
user.team = Team.first
user.save
(1..20).each do |i|
	task = Task.new 
	task.title = "Title # " +i.to_s
	task.is_complete = false
	task.is_open = false
	task.user = user
	task.team = user.team
	task.complete_on = Time.now.to_i
	task.save
end
# (1..20).each do |i|
# 	task = Task.new 
# 	task.title = "Title # " +i.to_s
# 	task.is_complete = false
# 	task.is_open = true
# 	task.team = user.team
# 	task.complete_on = Time.now.to_i
# 	task.save
# end