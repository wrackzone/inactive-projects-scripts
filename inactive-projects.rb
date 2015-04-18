# Identifies inactive projects 
# Barry Mullan, Rally Software (December 2014)

require 'rubygems'
require 'rally_api'
require 'json'
require 'csv'

class RallyInactiveProjects

	def initialize configFile

		print "Reading config file #{configFile}\n"
		print "Connecting to rally\n"
		print "Running in ", Dir.pwd,"\n"

		# connect to rally.
		#Setting custom headers
		headers = RallyAPI::CustomHttpHeader.new()
		headers.name = "InactiveProjects"
		headers.vendor = "Rally"
		headers.version = "1.0"

		#or one line custom header
		headers = RallyAPI::CustomHttpHeader.new({:vendor => "Vendor", :name => "Custom Name", :version => "1.0"})

		file = File.read(configFile)
		config_hash = JSON.parse(file)

		config = {:base_url => "https://rally1.rallydev.com/slm"}
		# config[:username]   = "username@rallydev.com"
		# config[:password]   = "pwd"
		config[:api_key]   = config_hash["api-key"] # "_y9sB5fixTWa1V36PTkOS8QOBpQngF0DNvndtpkw05w8"
		config[:workspace] = config_hash["workspace"]
		config[:headers]    = headers #from RallyAPI::CustomHttpHeader.new()

		@rally = RallyAPI::RallyRestJson.new(config)
		@workspace = find_workspace(config[:workspace])
		@active_since = Time.parse(config_hash["active-since"]).utc.iso8601
		@csv_file_name = config_hash["csv-file-name"]

		print "Workspace:#{@workspace["Name"]} active-since:#{@active_since}\n"

	end

	def find_workspace(name)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "workspace"
		test_query.fetch = "Name,ObjectID"
		test_query.page_size = 200       #optional - default is 200
		# test_query.limit = 1000          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = true
		test_query.order = "Name Asc"
		test_query.query_string = "(Name = \"#{name}\")"

		results = @rally.find(test_query)

		return results.first
	end
	
	def find_project(name)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "project"
		test_query.fetch = "Name,ObjectID"
		test_query.page_size = 200       #optional - default is 200
		test_query.limit = 1000          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = true
		test_query.order = "Name Asc"
		test_query.query_string = "(Name = \"#{name}\")"

		results = @rally.find(test_query)

		return results.first
	end

	def find_user(objectid)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "user"
		test_query.fetch = "Name,ObjectID,UserName,EmailAddress,DisplayName"
		test_query.page_size = 20       #optional - default is 200
		test_query.limit = 1000          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = true
		test_query.order = "Name Asc"
		test_query.query_string = "(ObjectID = \"#{objectid}\")"

		results = @rally.find(test_query)

		return results.first
	end

	def find_projects

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "project"
		test_query.fetch = "Name,Parent,State,ObjectID,Owner,TeamMembers,Children,CreationDate"
		test_query.page_size = 200       #optional - default is 200
		# test_query.limit = 1000          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = false
		test_query.order = "Name Asc"
		# test_query.query_string = "(Name = \"#{name}\")"
		test_query.workspace = @workspace

		results = @rally.find(test_query)
	end

	def find_artifacts_since project,active_since

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "artifact"
		test_query.fetch = "Name,ObjectID"
		test_query.page_size = 200       #optional - default is 200
		# test_query.limit = 1000          #optional - default is 99999
		test_query.project = project
		test_query.project_scope_up = false
		test_query.project_scope_down = false
		# test_query.order = "Name Asc"
		test_query.query_string = "(LastUpdateDate >= \"#{active_since}\")"
		test_query.workspace = @workspace

		results = @rally.find(test_query)
	end

	def find_test_case(name)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "testcase"
		test_query.fetch = "FormattedID,Name,ObjectID"
		test_query.page_size = 200       #optional - default is 200
		test_query.limit = 10          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = true
		test_query.order = "Name Asc"
		test_query.query_string = "(Name = \"#{name}\")"
		test_query.project = @project

		results = @rally.find(test_query)

		return results.first

	end

	def run
		projects = find_projects
		print "Found #{projects.length} projects\n"

		CSV.open(@csv_file_name, "wb") do |csv|
	  		csv << ["Project","Owner","EmailAddress","Parent","Artifacts","CreationDate"]
			projects.each { |project| 

				# Omit projects with open child projects
				openChildren = project["Children"].reject { |child| child["State"] == "Closed" }
				# print project["Name"],openChildren.length,"\n"
				next if openChildren.length > 0

				artifacts = find_artifacts_since project,@active_since
				
				# if project["Owner"] != nil
				# 	user = find_user( project["Owner"].ObjectID)
				# else
				# 	user = nil
				# end
				user = project["Owner"] ? find_user( project["Owner"].ObjectID) : nil

				userdisplay = user != nil ?  user["UserName"] : "(None)" 
				if (user != nil)
					if (user["DisplayName"] != nil)
						userdisplay = user["DisplayName"]
					else
						userdisplay = user["EmailAddress"]
					end
				else
					userdisplay = "(None)"
				end

				emaildisplay = user != nil ? user["EmailAddress"] : "(None)" 
				print "Project:#{project["Name"]} \t#{userdisplay} \tArtifacts since:\t#{artifacts.length}\n"

				# tm = project["TeamMembers"].size
				# project["TeamMembers"].each { |tm| 
				# 	print "\n",tm,"\n"
				# }
				# print "\n",tm,"\n"
				creationDate = Time.parse(project["CreationDate"]).strftime("%m/%d/%Y")
				#date = Time.parse(creationDate).strftime("%m/%d/%Y")
				csv << [project["Name"], userdisplay,emaildisplay, project["Parent"],artifacts.length,creationDate]
			}
		end
	end
end

if (!ARGV[0])
	print "Usage: ruby inactive-projects.rb config_file_name.json\n"
else
	rtr = RallyInactiveProjects.new ARGV[0]
	rtr.run
end

