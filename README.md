# Clarizen-Timesheet-API-Fun
Powershell Clarizen Timesheet Rest API Fun

Let me know what you think!

Features:
1. Authentication: The script allows the user to authenticate with the Clarizen API using their username and password credentials. It obtains an authentication header containing the session ID, which is used for subsequent API requests.

2. User Input Validation: The script prompts the user for various inputs, such as the number of weeks ahead to enter time for, the selection of week ranges, and the selection of tasks. It validates the user's input to ensure it falls within the specified range and handles single or multiple selections accordingly.

3. Week Range Generation: Based on the user's input for the number of weeks ahead, the script generates a list of week ranges. Each week range includes the start and end dates of the corresponding week.

4. Active Task Retrieval: The script retrieves the list of active tasks for the specified resource using the Clarizen API. It fetches the task names and IDs associated with the resource.

5. Task Selection: The user is prompted to select the desired tasks from the list of active tasks. The script allows multiple task selections and displays the selected task names for confirmation.

6. Timesheet Data Collection: For each selected task and week range, the script prompts the user to select the days to apply hours to. The user can choose specific days or select the whole week. The script then prompts for the number of hours to apply for each selected day or for the whole week.

7. Timesheet Creation/Update: The script checks if a timesheet already exists for the selected task, date, and resource. If no timesheet exists, it creates a new one using the provided hours. If a timesheet already exists, it updates the existing timesheet with the new hours.

8. Error Handling: The script includes error handling to catch and display any errors that occur during the execution of the script, providing informative error messages to the user.

Step-by-Step Flow:
1. The user is prompted to enter their Clarizen username and password for authentication.

2. The script authenticates the user with the Clarizen API using the provided credentials and obtains an authentication header.

3. The user is prompted to enter the username for the resource they want to enter time for.

4. The user is asked to enter the number of weeks ahead they want to enter time for (1-4 weeks).

5. Based on the selected number of weeks, the script generates a list of week ranges and displays them to the user.

6. The user is prompted to select the desired week ranges from the generated list. They can select multiple week ranges or choose the "All week ranges" option.

7. The script retrieves the list of active tasks for the specified resource using the Clarizen API.

8. The user is presented with the list of active tasks and prompted to select the desired tasks to charge time to. They can select multiple tasks.

9. For each selected task and week range, the user is prompted to select the days to apply hours to. They can choose specific days or select the whole week.

10. For each selected day, the user is prompted to enter the number of hours to apply. If the whole week is selected, the user enters the number of hours to apply for each day of the week.

11. The script collects the timesheet data based on the user's selections, including the action (create or update), task name, reported date, and duration.

12. A summary of the timesheets to be updated or created is displayed to the user for review.

13. The user is prompted to confirm if they want to proceed with updating or creating the timesheets.

14. If the user confirms, the script updates or creates the timesheets based on the collected data using the Clarizen API.

15. If the user cancels, no changes are made, and a message is displayed indicating that the operation was cancelled.

16. If any errors occur during the execution of the script, an error message is displayed to the user.
