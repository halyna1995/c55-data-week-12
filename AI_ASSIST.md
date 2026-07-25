# AI assistance log

<!-- Document at least one point where you used an LLM on this assignment.
     Never paste connection strings, passwords, or real data. Replace TODO. -->

## Use 1

**Prompt I sent:**

Docker Desktop was stuck on “Starting the Docker Engine”, and Windows showed that the paging file was too small. I asked what safe steps I could try without deleting my project data.

**What the model answered:** 

The model suggested restarting Windows, shutting down WSL, stopping unused Docker containers, and starting only one Astro project. It also warned me not to reset Docker to factory settings or remove Docker volumes because this could delete local Airflow data and settings.

**What I kept, changed, or discarded, and why:** 

I followed the safe steps: I restarted the computer, opened only the current project, and stopped containers from older projects. I did not uninstall Docker or delete any Docker volumes because I wanted to keep my local Airflow history and connection settings. I checked the result myself by running `docker ps` and reopening the Airflow interface. No passwords, connection strings, or private data were shared with the model.
