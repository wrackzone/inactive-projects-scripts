# Identifies inactive projects 
# Barry Mullan, Rally Software (December 2014)

require 'rubygems'
require 'nokogiri'
require 'rally_api'
require 'markaby'
require 'json'
require 'csv'
require 'logger'

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
		# config[:username]   = "user.name@domain.com"
		# config[:password]   = "Password"
		config[:api_key]   = config_hash["api-key"] # "_y9sB5fixTWa1V36PTkOS8QOBpQngF0DNvndtpkw05w8"
		config[:workspace] = config_hash["workspace"]
		config[:headers]    = headers #from RallyAPI::CustomHttpHeader.new()

		@rally = RallyAPI::RallyRestJson.new(config)
		@workspace 									= find_workspace(config[:workspace])
		@active_since 							= Time.parse(config_hash['active-since']).utc.iso8601
		@most_recent_creation_date	= Time.parse(config_hash['most_recent_creation_date']).utc.iso8601
		@csv_file_name 							= config_hash['csv-file-name']

		# Logger ------------------------------------------------------------
		@logger 				          	= Logger.new('./inactive_projects.log')
		@logger.progname 						= "Inactive Projects"
		@logger.level 		        	= Logger::DEBUG # UNKNOWN | FATAL | ERROR | WARN | INFO | DEBUG

		@logger.info "Workspace:#{@workspace['Name']} active-since:#{@active_since}\n"
	end

	def close_project(project)
		begin
			@logger.info "Closing #{project.name}"

			# check if there are any open child projects
			openChildren = project['Children'].reject { |child| child['State'] == 'Closed' }
			if openChildren.length > 0 then
				@logger.info "Project has [#{openChildren.length.to_s}] open child project#{openChildren.length > 1 ? 's' : ''}. Cannot close a parent project with open child projects"
				@logger.warn "Could not close Project[#{project.name}] because it had open child projects."
			else
				fields = {}
				fields[:state] = 'Closed'
				fields[:description] = close_reason(project)

				project.update(fields)
				@logger.info("Closed Project[#{project.name}]")
			end

		rescue Exception => e
			@logger.debug "Exception Closing Project[#{project.name}]\n\tMessage:#{e.message}"
		end
	end

	# pre-pend closing reason to the description.
	def close_reason(project)
		return "Project[#{project.name}] closed on #{Time.now.utc} due to ZERO activity since #{@active_since}\n #{project.description.to_s}"
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

	def find_subscription()

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "subscription"
		test_query.fetch = "Name,ObjectID,Workspaces"
		test_query.page_size = 200       #optional - default is 200
		# test_query.limit = 1000          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = true
		test_query.order = "Name Asc"
		#test_query.query_string = "(Name = \"#{name}\")"

		results = @rally.find(test_query)

		return results.first
	end
	
	def find_project(name)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "project"
		test_query.fetch = "Name,ObjectID,CreationDate"
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

	def find_parent_projects (ws)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "project"
		test_query.fetch = "Name,Parent,State,ObjectID,Owner,TeamMembers,Children,CreationDate"
		test_query.page_size = 200       #optional - default is 200
		# test_query.limit = 1000          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = false
		test_query.order = "Name Asc"
		# test_query.query_string = "((State =  \"Open\") and (Parent = null))"
		test_query.query_string = "(State =  \"Open\")"
		test_query.workspace = ws
		results = @rally.find(test_query)
	end

	def find_projects (most_recent_creation_date)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "project"
		test_query.fetch = "Name,Parent,State,ObjectID,Owner,TeamMembers,Children,CreationDate"
		test_query.page_size = 200       #optional - default is 200
		# test_query.limit = 1000          #optional - default is 99999
		test_query.project_scope_up = false
		test_query.project_scope_down = false
		test_query.order = "Name Asc"
		#test_query.query_string = "(CreationDate <  \"#{most_recent_creation_date}\")"
		test_query.workspace = @workspace

		results = @rally.find(test_query)
	end

	def find_artifacts_since (ws,project,active_since)

		test_query = RallyAPI::RallyQuery.new()
		test_query.type = "artifact"
		test_query.fetch = "Name,ObjectID"
		test_query.page_size = 200       #optional - default is 200
		# test_query.limit = 1000          #optional - default is 99999
		test_query.project = project
		test_query.project_scope_up = false
		test_query.project_scope_down = false
		# test_query.project_scope_down = true
		# test_query.order = "Name Asc"
		test_query.query_string = "(LastUpdateDate >= \"#{active_since}\")"
		test_query.workspace = ws #@workspace

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

	def process_workspace(ws,csv)

		projects = find_parent_projects(ws)

		# ws["Projects"].each { |project| 
		projects.each { |project|
				next if project["State"] == "Closed"

				# uncomment to report on top level only
				#next if project["Parent"] != nil

				# Omit projects with open child projects
				openChildren = project['Children'].reject { |child| child['State'] == 'Closed' }
				# print project["Name"],openChildren.length,"\n"
				
				# next if openChildren.length > 0

				artifacts = find_artifacts_since ws,project,@active_since
				# artifacts = []
				
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
				#print "Project:#{project["Name"]}\tCreated:#{project['CreationDate']}\tOwner:#{userdisplay} \tArtifacts Updated Since(#{@active_since}):\t#{artifacts.length}\n"
				print "."
				@logger.info "Project:#{project["Name"]}\tCreated:#{project['CreationDate']}\tOwner:#{userdisplay} \tArtifacts Updated Since(#{@active_since}):\t#{artifacts.length}\n"

				projectCreationDate = Time.parse(project["CreationDate"]).strftime("%m/%d/%Y")
				csv << [ws["Name"],project["Name"], userdisplay,emaildisplay, project["Parent"],artifacts.length,projectCreationDate]
		}
		print "\n"

	end	

	def run
		start_time = Time.now

		sub = find_subscription()
		print sub["Name"],"\n"

		CSV.open(@csv_file_name, "wb") do |csv|
			csv << ["Workspace","Project","Owner","EmailAddress","Parent","Artifacts Since(#{@active_since})","Project Creation Date"]
			sub["Workspaces"].each { |ws|
				print "\t",ws["Name"],"\n"
				csv << [ws["Name"]]
				if ws["State"] == "Open"
					begin
						process_workspace(ws,csv)
					rescue
						next
					end
				end
			}
		end
		@logger.info "Finished: elapsed time #{'%.1f' % ((Time.now - start_time)/60)} minutes."
	end
end

if (!ARGV[0])
	print "Usage: ruby inactive-projects.rb config_file_name.json\n"
	@logger.info "Usage: ruby inactive-projects.rb config_file_name.json\n"
else
	rtr = RallyInactiveProjects.new ARGV[0]
	rtr.run
end
