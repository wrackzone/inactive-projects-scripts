# inactive-projects-scripts
Ruby script to identify inactive projects created before a specific date in the past.

We use a config file to specify a couple of dates: 
  1) We want to count updates since some point in time. "active-since" No updates means no activity.
	1.1) The dates are in dd/mm/yyyy order. If you see a date conversion error, you probably put the month at the front.
  2) We want to ignore recently created projects("most_recent_creation_date"). These projects may have 
     no updates to artifacts because they really haven't gotten started.

The output file is a csv. 
Each row is a listing of a project older than the "most_recent_creation_date" with contact 
information (owner) and a count of updates since the cutoff-date ("active-since")

Optional Features
We can automatically close the projects where no updates have been made to any artifact since the date specified
in the @active_since variable. Simply un-comment that section in the "run" procedure.
