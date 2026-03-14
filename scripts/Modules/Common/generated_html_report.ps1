
# Helper function to recursively generate HTML for object properties
function Get-ObjectPropertiesHtml {
    param(
        [Parameter(Mandatory = $true)]
        $obj,
        [int]$level = 0
    )

    $indent = "&nbsp;&nbsp;" * $level
    $html = ""

    if ($obj -and $obj.PSObject) {
        foreach ($property in $obj.PSObject.Properties) {
            $name = $property.Name
            $value = $property.Value

            if ($null -eq $value) {
                $valueDisplay = "<span style='color: var(--muted);'>null</span>"
            } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
                if ($value.Count -eq 0) {
                    $valueDisplay = "<span style='color: var(--muted);'>[]</span>"
                } else {
                    $valueDisplay = "<div style='margin-left: 20px;'>[</div>"
                    foreach ($item in $value) {
                        if ($item -is [PSCustomObject] -or $item -is [hashtable]) {
                            $valueDisplay += "<div style='margin-left: 40px; margin-bottom: 5px; padding: 5px; border-left: 2px solid var(--border); background: rgba(124,92,255,.02);'>"
                            $valueDisplay += "{<br>"
                            $valueDisplay += Get-ObjectPropertiesHtml -obj $item -level ($level + 2)
                            $valueDisplay += "$indent&nbsp;&nbsp;}"
                            $valueDisplay += "</div>"
                        } else {
                            $valueDisplay += "<div style='margin-left: 40px; margin-bottom: 5px;'>$item</div>"
                        }
                    }
                    $valueDisplay += "<div style='margin-left: 20px;'>]</div>"
                }
            } elseif ($value -is [PSCustomObject] -or $value -is [hashtable]) {
                $valueDisplay = "<div style='margin-left: 20px; padding: 5px; border-left: 2px solid var(--border); background: rgba(124,92,255,.02);'>{<br>"
                $valueDisplay += Get-ObjectPropertiesHtml -obj $value -level ($level + 1)
                $valueDisplay += "$indent}</div>"
            } elseif ($value -is [string]) {
                $valueDisplay = "<span style='color: var(--brand);'>`"$value`"</span>"
            } else {
                $valueDisplay = "<span style='color: var(--accent);'>$value</span>"
            }

            $html += "$indent<span style='color: var(--good);'>`"$name`"</span>: $valueDisplay<br>`n"
        }
    }

    return $html
}

function New-PolicyHtmlReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$PolicyJson,

        [Parameter(Mandatory = $true)]
        [string]$OutputPath,

        [Parameter(Mandatory = $false)]
        [string]$TenantName = "Unknown Tenant",

        [Parameter(Mandatory = $false)]
        [string]$Owner = "XLR User",

        [Parameter(Mandatory = $false)]
        [string]$ChangeId = "N/A",

        [Parameter(Mandatory = $false)]
        [string]$XlrId = "N/A",

        [Parameter(Mandatory = $false)]
        [string]$ReportTitle = "Intune Policy Report"
    )

    # Convert JSON to PowerShell object
    try {
        $policyData = $PolicyJson | ConvertFrom-Json
    } catch {
        Write-Error "Invalid JSON provided for policy data"
        return $null
    }

    # Extract policy name
    $policyName = if ($policyData.displayName) {
        $policyData.displayName
    } elseif ($policyData.name) {
        $policyData.name
    } else {
        "Unnamed Policy"
    }

    # Extract policy ID
    $policyId = if ($policyData.id) {
        $policyData.id
    } else {
        "Unknown ID"
    }

    # Generate table rows for policy properties
    $tableRows = ""
    foreach ($property in $policyData.PSObject.Properties) {
        $name = $property.Name
        $value = $property.Value

        if ($name -eq "settings") {
            Write-Host "-----"$name
            # Display a reference to the detailed settings section
            $value = "Check detailed settings below"
        } elseif ($null -eq $value) {
            $value = ""
        } elseif ($value -is [System.Collections.IEnumerable] -and -not ($value -is [string])) {
            $value = $value -join ", "
        } elseif ($value -is [PSCustomObject] -or $value -is [hashtable]) {
            $value = $value | ConvertTo-Json -Depth 99 -Compress
        } else {
            $value = $value
        }

        $tableRows += "<tr><td>$name</td><td>$value</td></tr>`n"
    }

    # Generate settings HTML
    $settingsHtml = ""
    if ($policyData.settings -and $policyData.settings.Count -gt 0) {
        foreach ($setting in $policyData.settings) {
            $settingsHtml += "<div style='margin-bottom: 20px; padding: 10px; border: 1px solid var(--border); border-radius: 8px;'>"
            $settingsHtml += "<h4>Setting $($setting.id)</h4>"
            $settingsHtml += Get-ObjectPropertiesHtml -obj $setting -level 0
            $settingsHtml += "</div>`n"
        }
    } else {
        $settingsHtml = "<p>No settings found.</p>"
    }


    # CSS and HTML structure (referenced from GenerateIntunePolicyComparisonReport.ps1)
    $css = @"

:root{

  --bg:#0b0c10; --panel:#111218; --panel-2:#161824; --text:#e6e6e6; --muted:#a5adcb;

  --brand:#7c5cff; --brand-2:#4ecdc4; --accent:#ffb86b; --good:#2ecc71; --warn:#f1c40f; --bad:#e74c3c;

  --border:rgba(255,255,255,.08); --shadow:0 10px 30px rgba(0,0,0,.35);

  --radius-xxl:20px; --radius-xl:16px; --radius-lg:12px; --radius-sm:8px;

  --code: ui-monospace,SFMono-Regular,Menlo,Monaco,Consolas,"Liberation Mono","Courier New",monospace;

  --font: system-ui,-apple-system,"Segoe UI",Roboto,Helvetica,Arial,"Apple Color Emoji","Segoe UI Emoji";

}

@media (prefers-color-scheme: light){

  :root{ --bg:#f6f7fb; --panel:#ffffff; --panel-2:#f8f9ff; --text:#1b1e28; --muted:#4c5372; --border:rgba(0,0,0,.08); --shadow:0 8px 24px rgba(0,0,0,.08); }

}

*,*::before,*::after{box-sizing:border-box}

html,body{height:100%}

body{

  margin:0; font-family:var(--font); color:var(--text);

  background: radial-gradient(1200px 600px at 20% -10%, rgba(124,92,255,.18), transparent 60%),

              radial-gradient(900px 500px at 100% 0%, rgba(78,205,196,.12), transparent 50%),

              var(--bg);

  line-height:1.6;

}

a{color:var(--brand); text-decoration:none} a:hover{text-decoration:underline}

h1,h2,h3{line-height:1.2; margin:0 0 .4rem 0}

h1{font-size:clamp(1.8rem,2.5vw,2.4rem)}

h2{font-size:clamp(1.2rem,2vw,1.4rem); letter-spacing:.2px; color:var(--muted); font-weight:600}

h3{font-size:1.05rem; color:var(--muted); font-weight:600}

p{margin:.25rem 0 .75rem 0}

small,.muted{color:var(--muted)}

hr{border:none; border-top:1px solid var(--border); margin:1.25rem 0}

.container{max-width:1100px; margin:40px auto; padding:0 20px}

.header{

  background: linear-gradient(180deg, rgba(255,255,255,.06), transparent), var(--panel);

  border:1px solid var(--border); border-radius:20px; padding:28px; box-shadow:var(--shadow);

  display:grid; grid-template-columns:1fr auto; gap:16px; align-items:center;

}

.brand-pill{display:inline-flex; align-items:center; gap:.5rem; background:linear-gradient(135deg, rgba(124,92,255,.15), rgba(78,205,196,.12)); border:1px solid var(--border); padding:8px 12px; border-radius:999px; font-weight:600}

.meta{display:flex; flex-wrap:wrap; gap:10px}

.meta .tag{border:1px solid var(--border); background:var(--panel-2); border-radius:999px; padding:6px 10px; font-size:.85rem}

.grid{display:grid; gap:18px; margin-top:18px; grid-template-columns:repeat(12,1fr)}

.card{grid-column:span 4; background:var(--panel); border:1px solid var(--border); border-radius:16px; padding:18px; box-shadow:var(--shadow)}
.card2{grid-column:span 6; background:var(--panel); border:1px solid var(--border); border-radius:16px; padding:18px; box-shadow:var(--shadow)}

.card.wide{grid-column:span 8} .card.full{grid-column:1 / -1}

.card .kpi{display:flex; align-items:baseline; gap:12px; margin-top:6px}

.kpi .value{font-size:1rem; font-weight:100; letter-spacing:-.5px}

.kpi .delta.up{color:var(--good)} .kpi .delta.down{color:var(--bad)}

.progress{height:10px; background:var(--panel-2); border-radius:999px; overflow:hidden; border:1px solid var(--border)}

.progress > span{display:block; height:100%; background:linear-gradient(90deg, var(--brand), var(--brand-2))}

table{width:100%; border-collapse:collapse; font-size:.95rem}

thead th{text-align:left; padding:12px; background:var(--panel-2); border-bottom:1px solid var(--border); font-weight:700; letter-spacing:.2px}

tbody td{padding:12px; border-bottom:1px solid var(--border); vertical-align:top}

tbody tr:hover{background:rgba(124,92,255,.06)}

.status{display:inline-flex; align-items:center; gap:8px; font-weight:600}

.dot{width:10px; height:10px; border-radius:999px; background:var(--muted); display:inline-block}

.ok .dot{background:var(--good)} .warn .dot{background:var(--warn)} .bad .dot{background:var(--bad)}

.callout{border:1px solid var(--border); background:linear-gradient(180deg, rgba(124,92,255,.10), transparent); padding:16px; border-radius:12px}

pre,code{font-family:var(--code); font-size:.9rem; background:var(--panel-2); border:1px solid var(--border); border-radius:8px}

pre{padding:14px; overflow:auto}

.footer{margin:26px 0 50px; color:var(--muted); text-align:center; font-size:.9rem}

@media print{ body{background:#fff} .header,.card{box-shadow:none} }

"@

    # Meta tags
    $MetaTags = @("Owner: $owner","Run: $(Get-Date -f 'yyyy-MM-dd HH:mm')","Change Id: $ChangeId","XLR Job Id: $XlrId")

    # Build dynamic HTML fragments
    $metaHtml = ($MetaTags | ForEach-Object { "<span class='tag'>$_</span>" }) -join "`n"

    # Generate HTML content
    $html = @"
<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>$ReportTitle</title>
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>$css</style>
</head>
<body>
<div class="container">
<section class="header">
<div>
<div class="brand-pill"><img src="data:image/png;base64,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" width="150" height="30" alt="Report"/></div>
<div class="meta">$metaHtml</div>
</section>

<div class='card full'>
<h2 align='center'>$ReportTitle</h2>
</div>

<section class="grid">

    <div class='card2'>
<h3>Policy Details</h3>
<div class='kpi'>
<div class='value'>Tenant: $TenantName</div>
<div class='value'>Policy Name: $policyName</div>
<div class='value'>Policy ID: $policyId</div>
</div>
</div>

    <div class="card full">
<h3>Policy Properties</h3>
<table>
<thead>
<tr>
<th>Name</th><th>Value</th>
</tr>
</thead>
<tbody>
$tableRows
</tbody>
</table>
</div>

    <div class="card full">
<h3>Settings Details</h3>
$settingsHtml
</div>

    <div class="card full">
<h3>Notes & Callouts</h3>


</div>
</section>

<div class="footer">
    Generated by CaC workflow • $(Get-Date -f 'yyyy-MM-dd HH:mm')
</div>
</div>
</body>
</html>
"@

    # Write HTML to file
    try {
        $html | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "HTML report generated successfully at $OutputPath"
        return $OutputPath
    } catch {
        Write-Error "Failed to write HTML report to $OutputPath"
        return $null
    }
}