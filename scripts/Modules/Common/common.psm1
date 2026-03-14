function Compare-ArrayValues {
param (
        [Parameter(Mandatory = $true)]
        $SrcObject,

        [Parameter(Mandatory = $true)]
        $DstObject
    )
     $ComparisonResults=@{}
     $compArray= Compare-Object -ReferenceObject $SrcObject -DifferenceObject $DstObject
     if($compArray.count -eq 0)
     {
     $ComparisonResults["Result"]='Matching'
     } else {
     $ComparisonResults["Result"]='NotMatching'
     $ComparisonResults["missing_in_src"] = $compArray | ?{$_.sideIndicator -eq "=>"} | %{$_.InputObject}
     $ComparisonResults["missing_in_dst"] = $compArray | ?{$_.sideIndicator -eq "<="} | %{$_.InputObject}
     }
     Return $ComparisonResults    
}
function Get-NestedProperties {
    param (
        [Parameter(Mandatory = $true)]
        [PSCustomObject]$InputObject,

        [string]$Prefix = ''
    )

    $properties = @()
    $ignoredFields = @(
        "@odata.context", "id", "createdDateTime","@odata.type",
        "lastModifiedDateTime", "version", "roleScopeTagIds"
    )

    foreach ($property in $InputObject.PSObject.Properties) {
        $name = if ($Prefix) { "$Prefix.$($property.Name)" } else { $property.Name }
        $value = $property.Value
	foreach($field in $ignoredFields){
	$InputObject.psobject.Properties.Remove($field)
	}
	#write-host "$name : $($value -is [System.Management.Automation.PSCustomObject])"
        if ($value -is [System.Management.Automation.PSCustomObject]) {
            # Recursively get properties for nested object
            $nestedProperties = Get-NestedProperties -InputObject $value -Prefix $name
            $nestedProperties | ForEach-Object { $properties+=$_ }
        } elseif ($value -is [System.Collections.IEnumerable] -and !$value.GetType().Name.Equals('String')) {
            # Handle arrays of objects
            $index = 0
	    #$name[$index]=@()
            foreach ($item in $value) {
		#write-host "$name item: $($item -is [System.Management.Automation.PSCustomObject])"

		
                if ($item -is [System.Management.Automation.PSCustomObject]) {
                    $nestedProperties = Get-NestedProperties -InputObject $item -Prefix "$name[$index]"
                    $nestedProperties | ForEach-Object { $properties+=$_ }
                } else {
			#write-host "$name"

                    $properties+=$name
                }
                $index++
            }
        } else {
            $properties+=$name
        }
    }

    return $properties
}

function Get-NestedValue {
    param(
        [object]$Object,
        [string]$Path
    )
 
    $parts = $Path -split '\.'
    foreach ($p in $parts) {
        $Object = $Object.$p
    }
    return $Object
}

function Compare-IntunePolicyData {
param (
        [Parameter(Mandatory = $true)]
        $SrcObject,

        [Parameter(Mandatory = $true)]
        $DstObject
        
    )

    $missingObjectsInSrc = @{}
    $missingObjectsInDest = @{}

    if (($SrcObject -is [System.Management.Automation.PSCustomObject] ) -and ($DstObject -is [System.Management.Automation.PSCustomObject] )) {
        $srcprops=Get-NestedProperties -InputObject $SrcObject
        $srcprops1=$srcprops | %{$_ -replace '\[\d+\]',""} | Sort-Object -Unique
        $dstprops=Get-NestedProperties -InputObject $DstObject
        $dstprops1=$dstprops | %{$_ -replace '\[\d+\]',""} | Sort-Object -Unique
        $combineprops= $srcprops1+$dstprops1 | sort -Unique
        $sourcevalues=@{}
        $destinationvalues=@{}
        foreach($p in $combineprops) { 
            $v=Get-NestedValue -Object $SrcObject -Path $p
            if($v -ne $null){
                $sourcevalues[$p]=$v
            }
         }
        foreach($p in $combineprops) { 
            $v=Get-NestedValue -Object $DstObject -Path $p
            if($v -ne $null){
                $destinationvalues[$p]=$v
            }
         }
        $combinedkeys=$sourcevalues.Keys+$destinationvalues.Keys
        foreach($key in $combinedkeys){
            $srcvalue=$sourcevalues[$key]
            $dstvalue=$destinationvalues[$key]
            if(($srcvalue -eq $null) -and ($dstvalue -ne $null)){
                $missingObjectsInSrc[$key]=$dstvalue
            }elseif(($dstvalue -eq $null) -and ($srcvalue -ne $null)){
                $missingObjectsInDest[$key]=$srcvalue
            }else{
                if($srcvalue.GetType() -eq $dstvalue.GetType()){
                    if($srcvalue -is [System.Collections.IEnumerable] -and !$srcvalue.GetType().Name.Equals('String')){
                        $arrayComparisonResults=Compare-ArrayValues -SrcObject $srcvalue -DstObject $dstvalue
                        if($arrayComparisonResults["Result"] -eq 'NotMatching'){
                            if($arrayComparisonResults["missing_in_src"] -ne $null) {
                              $missingObjectsInSrc[$key]=$arrayComparisonResults["missing_in_src"]
                            }
                            if($arrayComparisonResults["missing_in_dst"] -ne $null) {
                              $missingObjectsInDest[$key]=$arrayComparisonResults["missing_in_dst"]
                            }
                         }
                    }else{
                        if($srcvalue -ne $dstvalue){
                            $missingObjectsInSrc[$key]=$dstvalue
                            $missingObjectsInDest[$key]=$srcvalue
                        }
                    }
                }
            }

       }
    
    }else{
    Write-Error -Message "looks like the input objects are not in right format"
    }
    $result=@{}
    if(($missingObjectsInSrc.Count -eq 0) -and ($missingObjectsInDest.Count -eq 0)){
    $result["status"]="Match"
    }else{
    $result["status"]="Mismatch"
    }
    $result['missing_in_src']=$missingObjectsInSrc
    $result['missing_in_dst']=$missingObjectsInDest
    
    return $result
}

Export-ModuleMember -Function Compare-ArrayValues, Get-NestedProperties, Get-NestedValue, Compare-IntunePolicyData