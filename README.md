<<<<<<< HEAD
# WPS_INTUNE_CaC
Repo for Intune Config As Code development
=======
# WPS_INTUNE_CaC - dev branch
Created Folder Structure for configuration and compliance policies.
Added a script folder for powershell scripts.
Each commit must follow this pattern:
<ChangeID>: <Action> policy in <Environment> - <Short description>

Example:
CHG-1023: Add policy in ADT - Add Setting Catalog – configuration policy

Required Fields:
•	ChangeID: Unique change identifier (e.g., CHG-1023 or INTUNE-567)
•	Action: One of the standardized verbs: Add, Update, Delete, Assign
•	Environment: One of DEV, ADT, PROD
•	Description: Short summary of the change
Documented Conventions (README)
Include the following documentation in README.md:
Git Commit Guidelines

All commits must follow this format:

"ChangeID": "Action" policy in "Environment" - "Short description"

Fields – 
**ChangeID**: Unique ticket or reference ID (e.g., CHG-1023) 
**Action**: Add, Update, Delete, Assign
**Environment**: DEV, ADT, PROD
**Short description**: Clear, concise summary of change

Examples
CHG-1045: Add policy in DEV - Add VPN config for dev laptops 
CHG-1046: Update policy in ADT - Increase password length
CHG-1047: Delete policy in PROD - Remove old BitLocker rule

>>>>>>> e378e502b8dff29dcd620608a9c3a3f644af6444
