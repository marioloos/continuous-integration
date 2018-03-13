<#
.SYNOPSIS
   With this Script one can automate Jenkins to merge bug fixes of a certain svn path(e.q. branch) to 
   another (e.q. trunk)
.DESCRIPTION
   The script will get all history entries of the svn source path beeing new since the last run.
   Then it checks the commit comment, for deciding, whether to merge the change or not.
   If the comment starts with an jira ticket id, the jira ticket will labeled with label "MERGED".
   One can then get a list in jira with all merged fixes to complete the release notes.
   
   The Script does currently not using a config file.
   All paramters are given by the jenkins job.
   In Jenkins the credentials can be securely be managed and injectes as environment variables.
   
   The LastBuildRevision parameter can be injected by jenkins as well.
   Create a file "svnrevfile.properties" with line "svn_revision=XXXX"into a file into the workspace of the merge project.
   The merge job can import it and inject it as environment variable and update the file after each run
   (Jenkins function "Inject environment variables to the build process")
 
.PARAMETER <paramName>
   Source : the source svn path (local), changes were made to
   Destination : the destination path (local), the changes will be merged to
   LastBuildRevision: the svn revision of the last sucessfull build in source path
   SvnUser : the svn user to use
   SvnPassword:  password of the svn user to use
   jiraUser: the jira user to use for updating tickets
   jiraPassword: the password of the jira user to use
.EXAMPLE
   <An example of using the script>
#>
param (
	[string]$Source,
	[string]$Destination,
	[string]$WorkDir,
	[string]$LastBuildRevision,
	[string]$SvnUser,
	[string]$SvnPassword,
	[string] $jiraUser,
	[string] $jiraPassword
)

# Get the current timestamp and create a time specific named log file
$Timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss");
$logfileName = "Patch_" + $Timestamp + ".log"
$logfile = join-path -path $WorkDir -childpath $logfileName;

#Global Array of succesful merged Revisions
$MergedRevisions = @()

#Only For Test, comment later
#$LastBuildRevision = 11644
$SourceUrl = ""
$LastExitCode = 0;

#region Logging Functions
function LogWrite {
    Param ([string]$logString, [string]$logLevel, [string]$ForeColor)
    $nowDate = Get-Date -format dd.MM.yyyy
    $nowTime = Get-Date -format HH:mm:ss
    if ($logLevel -eq "EMPTY") {
        Add-content $logfile -value "$logString"
        Write-Host "$logString" -ForegroundColor $ForeColor
    } else {
        Add-content $logfile -value "$logString" 
        Write-Host "$logString" -Foreground $ForeColor
    }    
}
function writeError($message) {
	#Write-Host $message -Foreground Red
	LogWrite $message "ERROR" Red
	$global:success = $false
	
	#to make sure, we have a bad exit code
	LogWrite "Setting Exit Code -1" "ERROR" Red
	exit -1
	#break;
}
function writeSuccess($message) {
	#Write-Host $message -Foreground Green
	LogWrite $message "STATUS" Green
}
function writeMessage($message) {
	#Write-Host $message -Foreground White
	LogWrite $message "INFO" White
}

#endregion

#region Initialization

#endregion

#region Directory Services

function CheckDirectory($Tag) {
   $return = $true
	$checkDirectory = $Tag.Replace('"', "")
	if ((test-path -path $checkDirectory) -eq $false -and $checkDirectory -ne "") {
		$return = $false
	}
	$return
}

#endregion

#region SVN Services

 function CreatePatch()
 {
 	Param([string]$oldRevision, [string] $newRevision)
	#Change to distination directory
	cd $Source
 	#writeMessage "Create Patch file ${$newRevision}.patch.."
	
	$filename = join-path -path $base -childpath ($newRevision  + ".patch")
	#svn diff -r $oldRevision:$newRevision | Out-File $filename -encoding Utf8
	svn diff  $SourceUrl@$oldRevision $SourceUrl@$newRevision  --trust-server-cert --non-interactive --username $SvnUser --password $SvnPassword | Out-File $filename -encoding Utf8
	
	$filename
 }
 
 function GetLog()
 {
    #Get newest changes of source path
	cd $Source
	#[xml] $changes = (svn diff -x BASE:PREV -x --ignore-eol-style --xml --summarize )
	[xml] $xmlData = svn log -r HEAD:$LastBuildRevision  --xml --trust-server-cert --non-interactive --username $SvnUser --password $SvnPassword
	
	#We need the list of log entries ordery ascending by revision
	$nodes = $xmlData.log.SelectNodes("logentry")	
	$list = ($nodes | Sort-Object -Property revision)
	
	$list
 }
 
 function ApplyPatch()
 {
 	Param([string] $patchfile, [string] $destination)
	
	#Change to distination directory
	cd $destination
	
	#writeMessage "Apply Patch file ${patchfile}..." 
	$result = svn patch $patchfile  --trust-server-cert --non-interactive --username $SvnUser --password $SvnPassword
	#writeMessage $result
	$result
 }
 
 function CommitPatch()
 {
	 Param([string] $destination, [string] $message)
	 
	 $message = "MERGE " + $message
	
	#Change to distination directory
	cd $destination
	#writeMessage "Commit ${destination} with message '${message}'" 
	$result = svn commit  --trust-server-cert --non-interactive --username $SvnUser --password $SvnPassword --message $message 
	
	#writeMessage $result
	
	$result
 }
 
 function GetUrl([string] $path)
 {
	# Change to physical local directory an retrieve the connected svn path
    cd $path
 	[xml] $info = svn info --xml --username $SvnUser --password $SvnPassword
	
	$url = $info.info.entry.url
	
	$url
 }


#endregion

#region Communication Servises

function SendMail()
{
 $url_src  = GetUrl($Source)
 $url_dst  = GetUrl($Destination)
 $patchlist = ($MergedRevisions -join "`n")
 $body     = "A merge was done triggered by a change of a svn path:`n`nDestination:   ${url_dst} `nSource:  ${url_src} `n`nMerged changes(patches): `n`n${patchlist}"
 $subject  = "Destination Path: ${url_dst} was beeing updated!"
 $encoding = ([System.Text.Encoding]::UTF8)
 $server   = "outlook.company.com"
 Get-ChildItem $logfile | Send-MailMessage -SmtpServer "${server}"  -to "employee1@company.com" -from "jenkins@company.com" -Subject "${subject}" -body "${body}"   -encoding $encoding
 Get-ChildItem $logfile | Send-MailMessage -SmtpServer "${server}"  -to "employee2@company.com" -from "jenkins@company.com" -Subject "${subject}" -body "${body}"   -encoding $encoding
 Get-ChildItem $logfile | Send-MailMessage -SmtpServer "${server}"  -to "employee3@company.com" -from "jenkins@company.com" -Subject "${subject}" -body "${body}"   -encoding $encoding
}

function ConvertTo-Base64($string) {
    $bytes  = [System.Text.Encoding]::UTF8.GetBytes($string);
    $encoded = [System.Convert]::ToBase64String($bytes);
    return $encoded;
}

#Using REST Interface to update jira ticket
function Jira_Add_Label([string]$issue,[string]$label) {
	#If the commit comment contains the jira ticket number, the ticket gets a label
	$enc = [system.Text.Encoding]::UTF8
    $body = "{ `"update`": { `"labels`": [ {`"add`": `"${label}`"} ] } }"
	$bytes = $enc.GetBytes($body)
	
	$Headers = New-Object -TypeName System.Net.WebHeaderCollection
    $b64 = ConvertTo-Base64 "${jiraUser}:${jiraPassword}"
    $Headers.Add("Authorization","Basic ${b64}")
    $Headers.Add("X-Atlassian-Token","nocheck")
	
	$WebRequest = [System.Net.WebRequest]::Create("https://portal.company.com/jira/rest/api/2/issue/${issue}")
	#editmeta
	$WebRequest.Method = "PUT"
	$WebRequest.Headers = $Headers
	$WebRequest.ContentType = "application/json"
	$WebRequest.ContentLength = $bytes.length
	
	$stm = $WebRequest.GetRequestStream();
	$stm.Write($bytes, 0, $bytes.length);
	#$stm.Close();
	$response = $WebRequest.GetResponse()
}

function UpdateJira()
{
 foreach($item in $MergedRevisions)
 {
   $matchList = @()
 	WriteMessage "Item: ${item}"
	
	#The Pattern of the ticket id's the projekt is using
 	$matchList += $item | Select-String -Pattern  "MTECB-\d{4}" -AllMatches | %{$_.matches} | %{$_.value} 
	
	$ticket = $matchList[0]	 
	WriteMessage "Ticket: ${ticket}"
	
	Jira_Add_Label $ticket "MERGED"
 }
}

#endregion

#region Main

$success = $false

WriteMessage "Last merged revision: ${LastBuildRevision}"
WriteMessage "Svn-User: ${SvnUser}"
WriteMessage ""

$SourceUrl = GetUrl $Source

#Aktuelles Arbeitsverzeichnis ausgeben
$base = join-path -path $WorkDir -childpath 'patches'
Get-Location | %{Write-Host "[INFO]" (Get-Date).ToString("[dd.MM.yyyy][HH:mm:ss]") "Working directory is "  $_}

if((CheckDirectory $base) -eq $false){
 mkdir $base
}

writeMessage ("Checking for new svn log entries (> ${LastBuildRevision})..")
$Logs = GetLog(1)

if($Logs -eq $null -or $Logs.length -eq 0 )
{
	writeMessage "No changes since last build"	
}
else
{
	$length = $Logs.length
	writeMessage ("${length} svn log entries found.")
	writeMessage ("Computing log entries...")
	writeMessage ("")
	
	$lastRev = $LastBuildRevision
	foreach($entry in $Logs)
	{
		$revision = $entry.revision
		$author   = $entry.author
		$message  = $entry.msg
		
		# here log entries could be ignored based on commit message rules and patterns (e.q. NOMERGE)
		
		if($revision -eq $LastBuildRevision.ToString()){
			continue;
		}
		
		writeMessage " ------------------------------------------------ "
		writeMessage ("|Revison " + "${revision}".PadRight(40, ' ') + "|")
		writeMessage ("|".PadRight(49, '-') + "|")
		writeMessage ("|Author: " + "${author}".PadRight(40, ' ') + "|")
		writeMessage ("|Message: " + "${message}".Substring(0,39).PadRight(39, ' ') + "|")
		writeMessage ("|".PadRight(49, '-'))
		
		writeMessage ("|Creating Patch...")
		$patch  = CreatePatch $lastRev $revision
		writeMessage ("|Patch created: " + "${patch}")
		writeMessage ("|".PadRight(49, '-'))
	
		writeMessage ("|Appling Patch ${$patch}")
		
		$apply = ApplyPatch $patch $Destination
		foreach($line in $apply)
		{		 
		 writeMessage ("|" + $line)
		 if($line.Contains("rejected"))
		 {
		 	WriteError "|"
		 	WriteError "| Appling Patch failed due to conflicts"
			writeMessage ("|".PadRight(49, '-'))
		 	$LastExitCode = -1;
			"svn_revision=${lastRev}" | Out-File "svnrevfile.properties" -encoding ASCII -Force
			exit -1;
		 }
		}
		
		writeMessage ("|".PadRight(49, '-'))
		writeMessage ("|Committing... ")
		
		
		$status = CommitPatch $Destination $message
		foreach($line in $status)
		{
			if($line -eq $null){
			 continue
			}
			writeMessage ("|" + $line)
		}
	
		writeMessage " ".PadRight(49, '-')
		
		writeMessage ""
				
		$lastRev = $revision
		$MergedRevisions += ("${revision}   -   ${author}   -   ${message}")
	}
	cd $Source 
	cd ..
	 "svn_revision=${lastRev}" | Out-File "svnrevfile.properties" -encoding ASCII -Force
	 
	 if("${lastRev}" -ne "${LastBuildRevision}")
	 {
	 	UpdateJira
	 	SendMail
	 }
	 else{
	  writeMessage "No changes since last build"
	 }
}
$success = $true;

#endregion