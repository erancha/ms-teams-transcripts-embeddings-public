# This script sets up the necessary Teams application access policy to allow the Azure AD app
# to access meeting transcripts across the organization.
#
# Prerequisites:
# - Azure AD app registration with Application permissions:
#   - OnlineMeetings.Read.All
#   - CallRecords.Read.All
#   - OnlineMeetingTranscript.Read.All
# - Global Administrator or Teams Administrator role in the target tenant
# - Azure AD tenant ID of the organization
#
# Usage:

# .\teams-app-access-policy.ps1 -TenantId "your-tenant-id"
#
# The script performs the following steps:
#   1. Installs the Microsoft Teams PowerShell module if not already installed
#   2. Connects to Microsoft Teams in the specified tenant (prompts for admin credentials)
#   3. Creates or updates the "TranscriptAccess" policy for our app
#   4. Grants the policy globally to allow transcript access across all users
#   5. Verifies the final policy configuration

param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId
)

# Check if MicrosoftTeams module is installed
if (-not (Get-Module -ListAvailable -Name MicrosoftTeams)) {
    Write-Host "Installing Microsoft Teams PowerShell module..."
    Install-Module -Name MicrosoftTeams -Force -AllowClobber -Scope CurrentUser
}

# Import the module
Import-Module MicrosoftTeams

# Connect to Microsoft Teams (will prompt for admin credentials)
Connect-MicrosoftTeams -TenantId $TenantId

# Check if the policy already exists
$existingPolicy = Get-CsApplicationAccessPolicy -Identity "TranscriptAccess" -ErrorAction SilentlyContinue

# Create or update the policy
if ($null -eq $existingPolicy) {
    Write-Host "Creating new application access policy..."
    New-CsApplicationAccessPolicy -Identity "TranscriptAccess" -AppIds "1a201a82-3f30-4357-b17f-342a6648394b" -Description "Allow access to meeting transcripts"
}
else {
    Write-Host "Policy already exists. Ensuring correct app ID is set..."
    Set-CsApplicationAccessPolicy -Identity "TranscriptAccess" -AppIds "1a201a82-3f30-4357-b17f-342a6648394b"
}

# Check if the policy is already granted globally
$globalPolicy = Get-CsApplicationAccessPolicy -Identity "Global" -ErrorAction SilentlyContinue

# Grant the policy globally if not already granted
if ($null -eq $globalPolicy -or $globalPolicy.AppIds -notcontains "1a201a82-3f30-4357-b17f-342a6648394b") {
    Write-Host "Granting policy globally..."
    Grant-CsApplicationAccessPolicy -PolicyName "TranscriptAccess" -Global
}
else {
    Write-Host "Policy is already granted globally"
}

# Verify final state
Write-Host "
Final Policy Status:"
Write-Host "\nAll Application Access Policies:"
$policies = Get-CsApplicationAccessPolicy
$policies | Format-List Identity, Description, AppIds

Write-Host "\nGlobal Policy Details:"
$globalPolicy = Get-CsApplicationAccessPolicy -Identity "Global" -ErrorAction SilentlyContinue
$globalPolicy | Format-List Identity, Description, AppIds

Write-Host "\nTranscriptAccess Policy Details:"
$transcriptPolicy = Get-CsApplicationAccessPolicy -Identity "TranscriptAccess" -ErrorAction SilentlyContinue
$transcriptPolicy | Format-List Identity, Description, AppIds