# Example build for PostgreSQL 15:
#    docker build --build-arg WIN_VER=ltsc2019 --build-arg EDB_FILEID=1258228 --tag postgres-windows:latest .

####
#### argument for Windows version must be set early
####
ARG WIN_VER

####
#### Download and prepare PostgreSQL for Windows
####
FROM mcr.microsoft.com/windows/servercore:${WIN_VER} as prepare

### Set the variables for EnterpriseDB
ARG EDB_FILEID
ENV EDB_FILEID $EDB_FILEID
ENV EDB_REPO https://get.enterprisedb.com/postgresql
ENV PG_ROOT 'C:\\pgsql'
#PG 15 -> FILEID = 1258228

##### Use PowerShell for the installation
SHELL ["powershell", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
RUN echo $PSVersionTable

### Install PowerShell v7
RUN $FILENAME = (Join-Path -Path $home -ChildPath Downloads\PowerShell-7.3.1-win-x64.msi) ; \
    Invoke-WebRequest -Uri https://github.com/PowerShell/PowerShell/releases/download/v7.3.1/PowerShell-7.3.1-win-x64.msi -Outfile $FILENAME ;  \
    Start-Process MSIEXEC.exe -ArgumentList '-i', $FILENAME, '/quiet', '/norestart' -NoNewWindow -Wait

SHELL ["pwsh", "-Command", "$ErrorActionPreference = 'Stop'; $ProgressPreference = 'SilentlyContinue';"]
RUN echo $PSVersionTable

### Download EnterpriseDB and remove cruft
RUN $URL1 = $('https://sbp.enterprisedb.com/getfile.jsp?fileid={0}' -f $env:EDB_FILEID) ; \
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ; \
    Invoke-WebRequest -Uri $URL1 -OutFile 'C:\\EnterpriseDB.zip' ; \
    Expand-Archive 'C:\\EnterpriseDB.zip' -DestinationPath 'C:\\' ; \
    Remove-Item -Path 'C:\\EnterpriseDB.zip' ; \
    Remove-Item -Recurse -Force -ErrorAction Ignore -Path 'C:\\pgsql\\doc' ; \
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path 'C:\\pgsql\\include' ; \
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path 'C:\\pgsql\\pgAdmin*' ; \
    Remove-Item -Recurse -Force -ErrorAction SilentlyContinue -Path 'C:\\pgsql\\StackBuilder' ;

### Make the sample config easier to munge (and "correct by default")
RUN $SAMPLE_FILE = $('{0}\\share\\postgresql.conf.sample' -f $env:PG_ROOT ) ; \
    $SAMPLE_CONF = Get-Content $SAMPLE_FILE ; \
    $SAMPLE_CONF = $SAMPLE_CONF -Replace '#listen_addresses = ''localhost''','listen_addresses = ''*''' ; \
    $SAMPLE_CONF | Set-Content $SAMPLE_FILE

### Install correct Visual C++ Redistributable Package
RUN if (($env:EDB_VER -like '9.*') -or ($env:EDB_VER -like '10.*')) { \
        Write-Host('Visual C++ 2013 Redistributable Package') ; \
        $URL2 = 'https://download.microsoft.com/download/2/E/6/2E61CFA4-993B-4DD4-91DA-3737CD5CD6E3/vcredist_x64.exe' ; \
    } else { \
        Write-Host('Visual C++ 2017 Redistributable Package') ; \
        $URL2 = 'https://download.visualstudio.microsoft.com/download/pr/11100230/15ccb3f02745c7b206ad10373cbca89b/VC_redist.x64.exe' ; \
    } ; \
    Invoke-WebRequest -Uri $URL2 -OutFile 'C:\\vcredist.exe' ; \
    Start-Process 'C:\\vcredist.exe' -Wait \
        -ArgumentList @( \
            '/install', \
            '/passive', \
            '/norestart' \
        )

# Determine new files installed by VC Redist
RUN Get-ChildItem -Path 'C:\\Windows\\System32' | Sort-Object -Property LastWriteTime | Select Name,LastWriteTime -First 25

# Copy relevant DLLs to PostgreSQL
RUN if (Test-Path 'C:\\windows\\system32\\msvcp120.dll') { \
        Write-Host('Visual C++ 2013 Redistributable Package') ; \
        Copy-Item 'C:\\windows\\system32\\msvcp120.dll' -Destination 'C:\\pgsql\\bin\\msvcp120.dll' ; \
        Copy-Item 'C:\\windows\\system32\\msvcr120.dll' -Destination 'C:\\pgsql\\bin\\msvcr120.dll' ; \
    } else { \
        Write-Host('Visual C++ 2017 Redistributable Package') ; \
        Copy-Item 'C:\\windows\\system32\\vcruntime140.dll' -Destination 'C:\\pgsql\\bin\\vcruntime140.dll' ; \
    }

####
#### PostgreSQL on Windows Nano Server
####
FROM mcr.microsoft.com/windows/servercore:${WIN_VER}

RUN mkdir "C:\\docker-entrypoint-initdb.d"

#### Copy over PostgreSQL
COPY --from=prepare /pgsql /pgsql

#### In order to set system PATH, ContainerAdministrator must be used
USER ContainerAdministrator
RUN setx /M PATH "C:\\pgsql\\bin;%PATH%"
USER ContainerUser
ENV PGDATA "C:\\pgsql\\data"

COPY docker-entrypoint.cmd /
#ENTRYPOINT ["C:\\docker-entrypoint.cmd"]

EXPOSE 5432
CMD ["powershell"]

#CMD ["postgres"]
#https://github.com/CesarBallardini/docker-postgres-windows

