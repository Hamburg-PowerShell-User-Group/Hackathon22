<#
.SYNOPSIS
Some ideas created by Thimo Limpert during the PSHackathon22
Se Readme for mor infos ;)
Tried to document everything. If you got questions ask right away ;)
#>


$ErrorActionPreference = "STOP"

#region prepare data
Expand-Archive ".\Passagierzahlen.zip" -DestinationPath ".\passagierzahlen2016"
Expand-Archive ".\passagierzahlen2009.zip"
$data2016 = Import-Csv -Path ".\passagierzahlen2016\Hackathon.csv" -Encoding windows-1252 -Delimiter ";"
$data2009 = Import-Csv -Path '.\passagierzahlen2009\Hackathon 2009.csv' -Encoding windows-1252 -Delimiter ";"
#endregion


#region stations
<#
.SYNOPSIS
Returns the usage (entrance and exits of stations)

.PARAMETER data
The data from the CSV

.EXAMPLE
See code below function ;)
#>
function Get-UsageOfStations {
    param (
        $data
    )
    $groups = $data | Group-Object -Property "Station", "strKurzbezeichnung"

    foreach ($group in $groups) {

        $output = [PSCustomObject]@{
            Station        = ($group.Name -split ",")[0]
            Train          = ($group.Name -split ",")[1]
            EinAustieg_Sum = 0
        }

        $group.Group | Measure-Object -Property "Einsteiger", "Aussteiger" -Sum -Average -StandardDeviation | % {
            $output | Add-Member -MemberType NoteProperty -Name "$($_.Property)_Sum" -Value $_.Sum
            $output | Add-Member -MemberType NoteProperty -Name "$($_.Property)_Count" -Value $_.Count
            $output | Add-Member -MemberType NoteProperty -Name "$($_.Property)_Average" -Value $_.Average
            $output | Add-Member -MemberType NoteProperty -Name "$($_.Property)_StandardDeviation)" -Value $_.StandardDeviation
            $output.EinAustieg_Sum = $output.EinAustieg_Sum + $_.Sum
        }
        $output
    }
}

$stations2009 = Get-UsageOfStations -data $data2009
$stations2016 = Get-UsageOfStations -data $data2016

<#
.SYNOPSIS
Outputs the Top used stations by Entrance, Exit or Sum

.PARAMETER stations
Stations outputted by Get-UsageofStations

.PARAMETER Top
Show top stations of each category.

.EXAMPLE
see below function

.NOTES
Probably should use a defined class or InputObject but I'm to lazy :D
#>
function Compare-FrequentedStations {
    param (
        $stations,
        [int]$Top = 5
    )
    $format = { $_.Station + $_.Train + ": Sum: " + $_.EinAustieg_Sum + " Entrance: " + $_.Einsteiger_Sum + " Exit: " + $_.Aussteiger_Sum }

    $Total = $stations | Sort-Object -Descending -Property EinAustieg_Sum -Top 5 | ForEach-Object -Process $format
    $Entrance = $stations | Sort-Object -Descending -Property Einsteiger_Sum -Top 5 | ForEach-Object -Process $format
    $Exit = $stations | Sort-Object -Descending -Property Aussteiger_Sum -Top 5 | ForEach-Object -Process $format

    for ($i = 0; $i -lt $Top; $i++) {
        [PSCustomObject]@{
            Total    = $Total[$i]
            Entrance = $Entrance[$i]
            Exit     = $Exit[$i]
        }
    }
}

Write-Output "---Stations from 2009"
Compare-FrequentedStations -stations $stations2009
Write-Output "---Station from 2016---"
Compare-FrequentedStations -stations $stations2016
#endregion


#region section
<#
.SYNOPSIS
Class to represent Sections
#>
class Section {
    $StartStation
    $StartStation_Entry
    $StartStation_Exit
    $EndStation
    $EndStation_Exit
    [int]$Passengers
    $Train
    $TrainNumber
    $Date
}

<#
.SYNOPSIS
Calculates the Passengers between two stations in a train (section)

.PARAMETER data
Data from CSV

.PARAMETER normalize
Should the function normalize the passenger number?
This means that if the passengers are below zero in an train, the passengernumber will be increased by the amount on all previous sections.
If not, the negative pessangers are just discarded and set to 0 for this section

.EXAMPLE
See run below function

.NOTES
General notes
#>
function Get-SectionPassengers {
    param (
        $data,
        [switch]$normalize
    )
    
    function Repair-Sections {
        param (
            $sections
        )
        $minimum = $sections | Measure-Object -Property Passengers -Minimum | Select-Object -ExpandProperty Minimum
        foreach ($section in $sections) {
            $section.Passengers = $section.Passengers - $minimum
        }
    }
    $sections = New-Object System.Collections.Generic.List[Section]

    for ($i = 0; $i -lt $data.Count; $i++) {

        if ($data[$i].Zugnr -eq $data[$i + 1].Zugnr) {
            $section = [Section]::new()
            $section.StartStation = $data[$i].Station
            $section.EndStation = $data[$i + 1].Station
            $section.Passengers = $sections.Count -eq 0 ? [double]::Parse($data[$i].Einsteiger, [CultureInfo]::CurrentCulture) : $sections[$sections.count - 1].Passengers + [double]::Parse($data[$i].Einsteiger, [CultureInfo]::CurrentCulture) - [double]::Parse($data[$i].Aussteiger, [CultureInfo]::CurrentCulture)
            $section.Train = $data[$i].strKurzbezeichnung
            $section.TrainNumber = $data[$i].Zugnr
            $section.StartStation_Entry = $data[$i].Einsteiger
            $section.StartStation_Exit = $data[$i].Aussteiger
            $section.EndStation_Exit = $data[$i + 1].Aussteiger
        
            $section.Date = $data[$i].dtmIstAbfahrtDatum
            if (-not $normalize.IsPresent) {
                $section.Passengers = $section.Passengers -lt 0 ?  0 : $section.Passengers    
            }

            $sections.Add($section)
        }
        elseif ($data[$i].Zugnr -ne $data[$i + 1].Zugnr -and $data[$i].Station -eq $data[$i + 1].Station -and $data[$i].strKurzbezeichnung -eq $data[$i + 1].strKurzbezeichnung) {
            $passengers = $sections.Count -eq 0 ? [double]::Parse($data[$i].Einsteiger, [CultureInfo]::CurrentCulture) : $sections[$i - 1].Passengers + [double]::Parse($data[$i].Einsteiger, [CultureInfo]::CurrentCulture) - [double]::Parse($data[$i].Aussteiger, [CultureInfo]::CurrentCulture)
            if ($passengers -ne 0 ) {
                #Write-Warning "Got $passengers on $($data[$i].Station) in $($data[$i].strKurzbezeichnung) on $($data[$i].dtmIstAbfahrtDatum))"
            }
            if ($normalize.IsPresent) {
                Repair-Sections $sections
            }
            Write-Output $sections
            $sections = New-Object System.Collections.Generic.List[Section]
        }
        else {
            if ($normalize.IsPresent) {
                Repair-Sections $sections
            }
            Write-Output $sections
            $sections = New-Object System.Collections.Generic.List[Section]
        }
    }
}

$sections2009 = Get-SectionPassengers -data $data2009
$sections2016 = Get-SectionPassengers -data $data2016

$normalizedSections2009 = Get-SectionPassengers -data $data2009 -normalize
$normalizedSections2016 = Get-SectionPassengers -data $data2016 -normalize

<#
.SYNOPSIS
Calculate SUm and Average of all sections regardless of train. Sorting by Sum

.PARAMETER sections
Sections to process

.PARAMETER Top
Return first objects sorted by sum

.EXAMPLE
see invocations belo
#>
function Get-MostLikedSections {
    param (
        [Section[]]$sections,
        [int]$Top = 5
    )
    $sections | Group-Object -Property StartStation, EndStation | ForEach-Object {
        $result = $_.Group | Measure-Object -Property Passengers -Sum -Average
        @{
            Section = $_.Name
            Sum     = $result.Sum
            Average = $result.Average
        }
    } | Sort-Object -Property Sum -Descending -Top $Top | ForEach-Object {[PSCustomObject]$_}
}


"2009","2016" | ForEach-Object {
    Write-Output "---TopSections of $_---"
    Get-MostLikedSections (Get-Variable "sections$_").Value
    Write-Output "---Top normalized Sections of $_---"
    Get-MostLikedSections (Get-Variable "normalizedSections$_").Value
}

Write-Output "I think i broke something during optimization. Maybe you find my mistakes ;)"


#endregion