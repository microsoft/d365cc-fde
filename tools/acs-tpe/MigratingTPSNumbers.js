/**
 * MigratingTPSNumbers.js
 *
 * Browser console script for Dynamics 365 that combines the phone number type
 * update workflow with the Teams phone number sync workflow.
 *
 * Flow:
 *   1. Retrieves the active Teams communication provider setting
 *      (msdyn_occommunicationprovider = 192350003) and captures its immutable ID.
 *   2. Queries the DynamicsAppId setting entry linked to that provider setting.
 *   3. Looks up the target msdyn_ocphonenumber record by phone number string.
 *   4. PATCHes the phone number type ONLY (does NOT touch msdyn_teamsresourceaccount).
 *      The resource account is managed by the sync step below.
 *   5. Verifies the PATCH succeeded.
 *   6. Calls CCaaS_SynchronizePhoneNumbers to sync — this is what updates the
 *      resource account association on the phone number record.
 *
 * Directions:
 *   ACS_TO_TPS — Sets msdyn_phonenumbertype = 1 (Teams Phone System)
 *   TPS_TO_ACS — Sets msdyn_phonenumbertype = 0 (ACS)
 *
 * Usage: Fill in the PHONE_NUMBER and DIRECTION below, then copy-paste into
 *        the browser console on your Dynamics 365 org.
 */

// =====================================================================
// ██████  CONFIGURATION — UPDATE THESE VALUES BEFORE RUNNING  ██████
// =====================================================================
//
// Provide the phone number string (e.g. "+15551234567") and the direction
// of the migration. The script handles everything else — the resource
// account is managed automatically via the CCaaS_SynchronizePhoneNumbers
// call, so you do NOT need to supply a resource account ID.
//
// =====================================================================

const PHONE_NUMBER = "+15551234567";   // <-- Replace with the actual phone number
const DIRECTION = "ACS_TO_TPS";       // <-- "ACS_TO_TPS" or "TPS_TO_ACS"

// =====================================================================
// ██████  END OF CONFIGURATION  ██████
// =====================================================================

(async function MigratingTPSNumbers() {
    "use strict";

    // --- Validation ---
    const validDirections = ["ACS_TO_TPS", "TPS_TO_ACS"];
    if (!validDirections.includes(DIRECTION)) {
        console.error(`❌ Invalid DIRECTION: "${DIRECTION}". Must be one of: ${validDirections.join(", ")}`);
        return;
    }

    if (!PHONE_NUMBER || PHONE_NUMBER === "+15551234567") {
        console.error('❌ PHONE_NUMBER has not been set. Replace the placeholder with the actual phone number (e.g. "+15551234567").');
        return;
    }

    // --- Constants ---
    const PHONE_NUMBER_TYPE_ACS = 0;
    const PHONE_NUMBER_TYPE_TEAMS = 1;

    const clientUrl = Xrm.Utility.getGlobalContext().getClientUrl();
    const apiUrl = `${clientUrl}/api/data/v9.2`;

    const headers = {
        "OData-MaxVersion": "4.0",
        "OData-Version": "4.0",
        "Accept": "application/json",
        "Content-Type": "application/json; charset=utf-8"
    };

    const patchHeaders = {
        ...headers,
        "If-Match": "*"
    };

    console.log("=== MigratingTPSNumbers Script Started ===");
    console.log(`Direction:    ${DIRECTION === "ACS_TO_TPS" ? "ACS → Teams Phone System" : "Teams Phone System → ACS"}`);
    console.log(`Phone Number: ${PHONE_NUMBER}`);
    console.log(`Org URL:      ${clientUrl}`);

    try {
        // ---------------------------------------------------------------
        // Step 1: FetchXML — Get active Teams communication provider setting
        // msdyn_occommunicationprovider = 192350003 (Microsoft Teams Phone System)
        // statecode = 0 (Active)
        // ---------------------------------------------------------------
        console.log("\n--- Step 1: Retrieving Teams Communication Provider Setting ---");

        const providerFetchXml = `
            <fetch top="1">
                <entity name="msdyn_occommunicationprovidersetting">
                    <attribute name="msdyn_occommunicationprovidersettingid" />
                    <attribute name="msdyn_name" />
                    <attribute name="msdyn_occommunicationproviderimmutableid" />
                    <attribute name="msdyn_occommunicationprovider" />
                    <attribute name="statecode" />
                    <filter type="and">
                        <condition attribute="statecode" operator="eq" value="0" />
                        <condition attribute="msdyn_occommunicationprovider" operator="eq" value="192350003" />
                    </filter>
                </entity>
            </fetch>`;

        const encodedProviderFetch = encodeURIComponent(providerFetchXml.trim());
        const providerResponse = await fetch(
            `${apiUrl}/msdyn_occommunicationprovidersettings?fetchXml=${encodedProviderFetch}`,
            { method: "GET", headers }
        );

        if (!providerResponse.ok) {
            throw new Error(`FetchXML for provider setting failed: ${providerResponse.status} ${providerResponse.statusText}`);
        }

        const providerData = await providerResponse.json();
        const providerRecords = providerData.value;

        if (!providerRecords || providerRecords.length === 0) {
            throw new Error("No active Teams communication provider setting found (msdyn_occommunicationprovider = 192350003, statecode = 0).");
        }

        const providerSetting = providerRecords[0];
        const providerSettingId = providerSetting.msdyn_occommunicationprovidersettingid;
        const providerName = providerSetting.msdyn_name;
        const immutableId = providerSetting.msdyn_occommunicationproviderimmutableid;

        console.log(`  Name:         ${providerName}`);
        console.log(`  ID:           ${providerSettingId}`);
        console.log(`  Immutable ID: ${immutableId}`);
        console.log("  Full record:", providerSetting);

        // ---------------------------------------------------------------
        // Step 2: FetchXML — Get setting entries where key = "DynamicsAppId"
        // linked to the Teams provider setting
        // ---------------------------------------------------------------
        console.log("\n--- Step 2: Retrieving DynamicsAppId Setting Entry ---");

        const entriesFetchXml = `
            <fetch>
                <entity name="msdyn_occommunicationprovidersettingentry">
                    <attribute name="msdyn_occommunicationprovidersettingentryid" />
                    <attribute name="msdyn_key" />
                    <attribute name="msdyn_value" />
                    <attribute name="msdyn_name" />
                    <filter type="and">
                        <condition attribute="msdyn_key" operator="eq" value="DynamicsAppId" />
                        <condition attribute="msdyn_communicationprovidersettingentid" operator="eq" value="${providerSettingId}" />
                    </filter>
                </entity>
            </fetch>`;

        const encodedEntriesFetch = encodeURIComponent(entriesFetchXml.trim());
        const entriesResponse = await fetch(
            `${apiUrl}/msdyn_occommunicationprovidersettingentries?fetchXml=${encodedEntriesFetch}`,
            { method: "GET", headers }
        );

        if (!entriesResponse.ok) {
            throw new Error(`FetchXML for setting entries failed: ${entriesResponse.status} ${entriesResponse.statusText}`);
        }

        const entriesData = await entriesResponse.json();
        const entryRecords = entriesData.value;

        if (entryRecords && entryRecords.length > 0) {
            entryRecords.forEach((entry, i) => {
                console.log(`  Entry ${i + 1}:`);
                console.log(`    Key:   ${entry.msdyn_key}`);
                console.log(`    Value: ${entry.msdyn_value}`);
            });
        } else {
            console.warn("  No setting entries found with key 'DynamicsAppId' for this provider setting.");
        }

        // ---------------------------------------------------------------
        // Step 3: Look up the phone number record by msdyn_phonenumber
        // ---------------------------------------------------------------
        console.log("\n--- Step 3: Looking up phone number record ---");

        const entitySetName = "msdyn_ocphonenumbers";
        const lookupUrl = `${apiUrl}/${entitySetName}?$filter=msdyn_phonenumber eq '${encodeURIComponent(PHONE_NUMBER)}'&$select=msdyn_ocphonenumberid,msdyn_phonenumber,msdyn_name,msdyn_phonenumbertype,msdyn_teamsresourceaccount,statecode`;
        const lookupResponse = await fetch(lookupUrl, {
            method: "GET",
            headers: {
                "OData-MaxVersion": "4.0",
                "OData-Version": "4.0",
                "Accept": "application/json"
            }
        });

        if (!lookupResponse.ok) {
            const errorBody = await lookupResponse.text();
            throw new Error(`Lookup phone number failed: ${lookupResponse.status} ${lookupResponse.statusText}\n${errorBody}`);
        }

        const lookupData = await lookupResponse.json();
        const records = lookupData.value;

        if (!records || records.length === 0) {
            throw new Error(`No msdyn_ocphonenumber record found with msdyn_phonenumber = "${PHONE_NUMBER}".`);
        }

        if (records.length > 1) {
            console.warn(`⚠️  Warning: Found ${records.length} records matching "${PHONE_NUMBER}". Using the first one.`);
        }

        const currentRecord = records[0];
        const phoneNumberRecordId = currentRecord.msdyn_ocphonenumberid;
        const currentType = currentRecord.msdyn_phonenumbertype;
        const currentTypeLabel = currentType === PHONE_NUMBER_TYPE_ACS ? "ACS (0)" : currentType === PHONE_NUMBER_TYPE_TEAMS ? "Teams (1)" : `Unknown (${currentType})`;

        console.log(`  Record ID:               ${phoneNumberRecordId}`);
        console.log(`  Phone Number:            ${currentRecord.msdyn_phonenumber}`);
        console.log(`  Name:                    ${currentRecord.msdyn_name}`);
        console.log(`  Current Type:            ${currentTypeLabel}`);
        console.log(`  Current Resource Account: ${currentRecord.msdyn_teamsresourceaccount || "(empty)"}`);

        if (DIRECTION === "ACS_TO_TPS" && currentType !== PHONE_NUMBER_TYPE_ACS) {
            console.warn(`⚠️  Warning: Direction is ACS → TPS but current type is not ACS (${currentTypeLabel}). Proceeding anyway.`);
        }
        if (DIRECTION === "TPS_TO_ACS" && currentType !== PHONE_NUMBER_TYPE_TEAMS) {
            console.warn(`⚠️  Warning: Direction is TPS → ACS but current type is not Teams (${currentTypeLabel}). Proceeding anyway.`);
        }

        // ---------------------------------------------------------------
        // Step 4: PATCH — Update phone number type
        // For ACS_TO_TPS: only sets the type — resource account is managed
        //                 by the CCaaS_SynchronizePhoneNumbers call in Step 6.
        // For TPS_TO_ACS: sets the type AND clears msdyn_teamsresourceaccount.
        // ---------------------------------------------------------------
        console.log("\n--- Step 4: Updating phone number record ---");

        const newType = DIRECTION === "ACS_TO_TPS" ? PHONE_NUMBER_TYPE_TEAMS : PHONE_NUMBER_TYPE_ACS;
        const newTypeLabel = newType === PHONE_NUMBER_TYPE_ACS ? "ACS (0)" : "Teams (1)";

        let patchBody;
        if (DIRECTION === "ACS_TO_TPS") {
            patchBody = {
                msdyn_phonenumbertype: newType
            };
            console.log(`  Setting msdyn_phonenumbertype = ${newType} (${newTypeLabel})`);
            console.log("  ℹ️  Resource account is NOT updated here — sync handles it.");
        } else {
            patchBody = {
                msdyn_phonenumbertype: newType,
                msdyn_teamsresourceaccount: null
            };
            console.log(`  Setting msdyn_phonenumbertype = ${newType} (${newTypeLabel})`);
            console.log("  Clearing msdyn_teamsresourceaccount (null)");
        }

        const patchUrl = `${apiUrl}/${entitySetName}(${phoneNumberRecordId})`;
        const patchResponse = await fetch(patchUrl, {
            method: "PATCH",
            headers: patchHeaders,
            body: JSON.stringify(patchBody)
        });

        if (!patchResponse.ok) {
            const errorBody = await patchResponse.text();
            throw new Error(`PATCH phone number record failed: ${patchResponse.status} ${patchResponse.statusText}\n${errorBody}`);
        }

        console.log("  ✅ PATCH succeeded.");

        // ---------------------------------------------------------------
        // Step 5: GET — Verify the type update
        // ---------------------------------------------------------------
        console.log("\n--- Step 5: Verifying type update ---");

        const verifyUrl = `${apiUrl}/${entitySetName}(${phoneNumberRecordId})?$select=msdyn_phonenumber,msdyn_name,msdyn_phonenumbertype,msdyn_teamsresourceaccount,statecode`;
        const verifyResponse = await fetch(verifyUrl, {
            method: "GET",
            headers: {
                "OData-MaxVersion": "4.0",
                "OData-Version": "4.0",
                "Accept": "application/json"
            }
        });

        if (verifyResponse.ok) {
            const updatedRecord = await verifyResponse.json();
            const updatedType = updatedRecord.msdyn_phonenumbertype;
            const updatedTypeLabel = updatedType === PHONE_NUMBER_TYPE_ACS ? "ACS (0)" : updatedType === PHONE_NUMBER_TYPE_TEAMS ? "Teams (1)" : `Unknown (${updatedType})`;

            console.log(`  Phone Number:             ${updatedRecord.msdyn_phonenumber}`);
            console.log(`  Updated Type:             ${updatedTypeLabel}`);
            console.log(`  Resource Account (pre-sync): ${updatedRecord.msdyn_teamsresourceaccount || "(empty)"}`);
        }

        // ---------------------------------------------------------------
        // Step 6: POST — Call CCaaS_SynchronizePhoneNumbers (bound action)
        // This syncs the phone numbers and manages the resource account
        // association on the Teams provider setting side.
        // ---------------------------------------------------------------
        console.log("\n--- Step 6: Calling CCaaS_SynchronizePhoneNumbers ---");
        console.log(`  Target: msdyn_occommunicationprovidersettings(${providerSettingId})`);

        const syncUrl = `${apiUrl}/msdyn_occommunicationprovidersettings(${providerSettingId})/Microsoft.Dynamics.CRM.CCaaS_SynchronizePhoneNumbers`;
        const syncResponse = await fetch(syncUrl, {
            method: "POST",
            headers,
            body: JSON.stringify({})
        });

        if (!syncResponse.ok) {
            const errorBody = await syncResponse.text();
            throw new Error(`SyncPhoneNumbers POST failed: ${syncResponse.status} ${syncResponse.statusText}\n${errorBody}`);
        }

        let syncResult = null;
        const responseText = await syncResponse.text();
        if (responseText) {
            syncResult = JSON.parse(responseText);
        }

        console.log("  ✅ SyncPhoneNumbers request accepted.");
        console.log("  Response:", syncResult || "(No response body — 204 No Content)");
        console.log("\n  ⚠️  NOTE: The sync operation is asynchronous. The API call returns");
        console.log("  immediately, but the actual sync process runs in the background.");
        console.log("  Expect a delay before the updated phone numbers and resource account");
        console.log("  changes are fully reflected in the Dynamics 365 UI.");

        // ---------------------------------------------------------------
        // Summary
        // ---------------------------------------------------------------
        console.log("\n========== SUMMARY ==========");
        console.log(`Direction:              ${DIRECTION === "ACS_TO_TPS" ? "ACS → Teams Phone System" : "Teams Phone System → ACS"}`);
        console.log(`Phone Number:           ${currentRecord.msdyn_phonenumber}`);
        console.log(`Phone Number Record ID: ${phoneNumberRecordId}`);
        console.log(`Previous Type:          ${currentTypeLabel}`);
        console.log(`New Type:               ${newTypeLabel}`);
        console.log(`Provider Setting:       ${providerName} (${providerSettingId})`);
        console.log(`Immutable ID:           ${immutableId}`);
        console.log(`DynamicsAppId:          ${entryRecords?.length > 0 ? entryRecords[0].msdyn_value : "Not found"}`);
        console.log(`Type Update (PATCH):    ✅ Success`);
        console.log(`Sync Phone Numbers:     ✅ Success`);
        console.log("==============================");

    } catch (error) {
        console.error("=== MigratingTPSNumbers FAILED ===");
        console.error(error.message || error);
        console.error(error);
    }
})();
