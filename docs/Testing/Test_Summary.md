# **Testing Results - Requirement 13**



##### **Test Summary**



The test\_sysaudit.sh script was used to perform 29 different automated tests on the System Health and Auditing Daemon project.



##### 

##### **Results On Main Ubuntu Environment**



* Tests total: 29
* Passed: 29
* Failed: 0



All tests have passed on the main Ubuntu VM.





##### **Results On Main Ubuntu Environment**



We also tested the script on another Ubuntu environment.



We initially had tests 2-4 fail due to differences in Linux usernames, however after making a slight modification to the test\_sysaudit.sh bash script we can confirm that tests 2-4 are passing on another Linux environments.



Test 13 on the other hand which runs audit file compression, is encountering a segmentation fault on another Ubuntu environment, the issue still remains unsolved and we suspect it's due to an environment problem and not necessarily a code problem.





##### **Summary**



All 29 tests have passed through the main Ubuntu Linux VM, however there seems to be a segmentation stop from test 13 on another Linux environment.



There are screenshots that provide evidence of the successful test runs on the primary Ubuntu VM.

