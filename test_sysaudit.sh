#!/bin/bash
FAILURES=0

#Configuring the test environment for multiple linux usernames

CURRENT_USER="$(id -un)"
sed -i "s/^AUTHORIZED_USER=.*/AUTHORIZED_USER=$CURRENT_USER/" test_security/sysaudit.cfg


#Test 1: Testing the help command

echo "Test 1: The Help Command"

bash sysaudit.sh --help

if [[ $? -eq 0 ]]; then
	echo "[PASSED] The help command is working!"
else
	echo "[FAILED] The help command has failed!"
	((FAILURES+=1))

fi

#Test 2: Testing any invalid command-line option

echo ""
echo "Test 2: Invalid Command-Line Option"

bash test_security/sysaudit.sh --invalid-option

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Invalid option was denied!"
else
	echo "[FAILED] Invalid option test has failed!"
	((FAILURES+=1))

fi

#Test 3: Testing for invalid storage limits

echo ""
echo "Test 3: Invalid Storage Limit"

bash test_security/sysaudit.sh --storage-limit 0

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Zero storage limit was denied!"
else
	echo "[FAILED] Zero storage limit test has failed!"
	((FAILURES+=1))

fi

#Test 4: Testing invalid scan intervals for 0

echo ""
echo "Test 4: Invalid Scan Intervals For 0"

bash test_security/sysaudit.sh --scan-interval 0

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Scan interval was denied for 0!"
else
	echo "[FAILED] Scan interval test failed for 0!"
	((FAILURES+=1))

fi

#Test 5: Testing for invalid archive hour - 24

echo ""
echo "Test 5: Invalid Archive Hour"

bash test_environment/sysaudit.sh --scan-interval 60

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Invalid archive hour was denied!"
else
	echo "[FAILED] Invalid archive hour has failed!"
	((FAILURES+=1))

fi

#Test 6: Testing valid archive hour - 0 to 23

echo ""
echo "Test 6: Valid Archive Hour"

bash test_valid_config/sysaudit.sh --scan-interval 60

if [[ $? -eq 0 ]]; then
	echo "[PASSED] Archive hour is valid!"
else
	echo "[FAILED] Archive hour has failed!"
	((FAILURES+=1))

fi

#Test 7: Testing for any missing config files

echo ""
echo "Test 7: Missing Config Files"

bash test_missing_config/sysaudit.sh --scan-interval 60

if [[ $? -eq 3 ]]; then
	echo "[PASSED] Missing config file was detected!"
else
	echo "[FAILED] Missing config file test failed!"
	((FAILURES+=1))

fi

#Test 8: Testing for empty configuration setting for storage limit

echo ""
echo "Test 8: Empty config setting"

bash test_empty_config/sysaudit.sh --scan-interval 60

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Empty config setting was detected!"
else
	echo "[FAILED] Empty config test has failed!"
	((FAILURES+=1))

fi

#Test 9: Testing for Invalid configuration line

echo ""
echo "Test 9: Invalid config line"

bash test_invalid_line/sysaudit.sh --scan-interval 60

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Invalid config line was denied!"
else
	echo "[FAILED] Invalid config test has failed!"
	((FAILURES+=1))

fi

#Test 10: Adding an unknown setting

echo ""
echo "Test 10: Adding an unknown setting"

bash test_unknown_setting/sysaudit.sh --scan-interval 60

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Unknown config setting was denied!"
else
	echo "[FAILED] Unknown config setting test has failed!"
	((FAILURES+=1))

fi

#Test 11: Testing for zero archive interval

echo ""
echo "Test 11: Zero archive interval"

bash test_zero_interval/sysaudit.sh --scan-interval 60

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Zero archive interval was denied!"
else
	echo "[FAILED] Zero archive interval test has failed!"
	((FAILURES+=1))

fi

#Test 12: Testing for zero retention days

echo ""
echo "Test 12: Zero retention days"

bash test_zero_retention/sysaudit.sh --scan-interval 60

if [[ $? -eq 1 ]]; then
	echo "[PASSED] Zero retention days was denied!"
else
	echo "[FAILED] Zero retention days test has failed!"
	((FAILURES+=1))

fi

#Test 13: Testing compression functionality

echo ""
echo "Test 13: Compressing the audit files"

mkdir -p test_audit/raw test_audit/archive

rm -f test_audit/archive/audit_*

echo "Test record 1" > test_audit/raw/test1.audit
echo "Test record 2" > test_audit/raw/test2.audit

source Bandhna.K.sh

AUDIT_DIR="$PWD/test_audit/raw"
ARCHIVE_DIR="$PWD/test_audit/archive"
RAW_FILE_EXTENSION=".audit"
ARCHIVE_EXTENSION=".tar.gz"

if compress_audit_files; then
	if [[ -z "$(ls -A test_audit/raw)" ]] &&
	tar -tzf test_audit/archive/audit_* | grep -q "test1.audit" &&
	tar -tzf test_audit/archive/audit_* | grep -q "test2.audit"; then
	echo " [PASSED] Audit files were successfully compressed!"
else
	echo "[FAILED] Compression of audit files failed!"
	((FAILURES+=1))

fi

else
	echo "[FAILED] Compression function has failed!"
	((FAILURES+=1))

fi


#Test 14: Creating a function to clean archive files

echo ""
echo "Test 14: Archive cleanup"

mkdir -p test_audit/archive

touch test_audit/archive/old_archive.tar.gz
touch -d "3 days ago" test_audit/archive/old_archive.tar.gz

RETENTION_DAYS=1
source Bandhna.K.sh

delete_old_archives

if [[ ! -f test_audit/archive/old_archive.tar.gz ]]; then
	echo "[PASSED] The old archive was deleted successfully!"
else
	echo "[FAILED] The old archive has not been deleted!"
	((FAILURES+=1))

fi

#Test 15: Testing scheduling run

echo ""
echo "Test 15: First scheduling run"

rm -f .last_archive_run

TEST_MODE=1 bash BK_scheduler.sh > scheduler_test_output.txt

if grep -q "All scheduled maintenance tasks completed" scheduler_test_output.txt; then
	echo "[PASSED] The scheduler ran successfully on the first attempt!"
else
	echo "[FAILED] The scheduler failed to run!"
	((FAILURES+=1))

fi

rm -f .last_archive_run scheduler_test_output.txt

#Test 16: Scheduling run will skip if the interval has not been reached

echo ""
echo "Test 16: Schedule skip"

date +%s > .last_archive_run

TEST_MODE=1 bash BK_scheduler.sh > scheduler_test_output.txt

if grep -q "Three-day interval has not passed" scheduler_test_output.txt; then
	echo "[PASSED] Scheduler skipped successfully!"
else
	echo "[FAILED] Scheduler failed to skip!"
	((FAILURES+=1))

fi

rm -f .last_archive_run scheduler_test_output.txt

#Test 17: Invalid scheduling

echo ""
echo "Test 17: Invalid scheduling"

echo "Invalid!" > .last_archive_run

TEST_MODE=1 bash BK_scheduler.sh > scheduler_test_output.txt 2>&1

if grep -q "Invalid scheduler state file" scheduler_test_output.txt; then
	echo "[PASSED] Scheduler rejected the invalid scheduling!"
else
	echo "[FAILED] Scheduler didn't reject the invalid scheduling!"
	((FAILURES+=1))

fi

rm -f .last_archive_run scheduler_test_output.txt

#Test 18: Testing if it shows info about logging message

echo ""
echo "Test 18: Logging message"

LOG_FILE="test_log.txt"
source ./logging.sh

rm -f "$LOG_FILE"

log_info "Test info message"

if grep -q "\[INFO\] Test info message" "$LOG_FILE"; then
	echo "[PASSED] Info log message was successful!"
else
	echo "[FAILED} Info message was not logged!"
	((FAILURES+=1))

fi

rm -f "$LOG_FILE"

#Test 19: Displaying a warning log message

echo ""
echo "Test 19: Warning log message"

LOG_FILE="test_log.txt"
rm -f "$LOG_FILE"

log_warning "Test warning message"

if grep -q "\[WARNING\] Test warning message" "$LOG_FILE"; then
	echo "[PASSED] Warning log message was successful!"
else
	echo "[FAILED] Warning message was not displayed!"
	((FAILURES+=1))

fi

rm -f "$LOG_FILE"

#Test 20: Displaying an error message

echo ""
echo "Test 20: Error log message"

LOG_FILE="test_log.txt"
rm -f "$LOG_FILE"

log_error "Test error message"

if grep -q "\[ERROR\] Test error message" "$LOG_FILE"; then
	echo "[PASSED] Error log message was successful!"
else
	echo "[FAILED] Error message was not displayed!"
	((FAILURES+=1))

fi

rm -f "$LOG_FILE"

#Test 21: Testing error handling

echo ""
echo "Test 21: Error handling"

source ./error_handler.sh

handle_error "Test error message" 2 2> error_test_output.txt
result=$?

if [[ "$result" -eq 2 ]] && grep -q "Test error message" error_test_output.txt; then
	echo "[PASSED] Error handler works!"
else
	echo "[FAILED] Error handler failed!"
	((FAILURES+=1))

fi

rm -f error_test_output.txt

#Test 22: Invalid error exit code 1"

echo ""
echo "Test 22: Invalid error exit code"

handle_error "Invalid exit code test" abc 2> error_test_output.txt
result=$?

if [[ "$result" -eq 1 ]] && grep -q "Invalid exit code test" error_test_output.txt; then
	echo "[PASSED] Invalid exit code is working!"
else
	echo "[FAILED] Invalid exit code is not working!"
	((FAILURES+=1))

fi

rm -f error_test_output.txt

#Test 23: Fatal error handling

echo ""
echo "Test 23: Fatal error handling"

bash -c 'source ./error_handler.sh; fatal_error "Fatal test message" 3' 2> error_test_output.txt
result=$?

if [[ "$result" -eq 3 ]] && grep -q "Fatal test message" error_test_output.txt; then
	echo "[PASSED] Fatal error handler is working!"
else
	echo "[FAILED] Fatal error handler is not working!"
	((FAILURES+=1))

fi

rm -f error_test_output.txt

#Test 24: Automatic exit handling

echo ""
echo "Test 24: Automatic exit handling"

LOG_FILE="test_log.txt"

bash -c 'LOG_FILE="test_log.txt"; source ./logging.sh; source ./error_handler.sh; install_error_traps; exit 5' 2> error_test_output.txt

if grep -q "Program stopped with exit code: 5" "$LOG_FILE"; then
	echo "[PASSED] Automatic exit handling is working!"
else
	echo "[FAILED] Automatic exit handling failed!"
	((FAILURES+=1))

fi

rm -f "$LOG_FILE" error_test_output.txt

#Test 25: Testing the storage within the limit

echo ""
echo "Test 25: Storage within its limits"

source ./storage_check.sh

AUDIT_DIR=$(mktemp -d)
LOG_FILE="test_storage_log.txt"
STORAGE_LIMIT_MB=1

rm -f "$LOG_FILE"

check_storage
result=$?

if grep -q "Audit storage is within limit" "$LOG_FILE"; then
	echo "[PASSED] Storage is within its limits!"
else
	echo "[FAILED] Storage limit test has failed!"
	((FAILURES+=1))

fi

rm -rf "$AUDIT_DIR" "$LOG_FILE"

#Test 26: Testing when storage limit is maxed out

echo ""
echo "Test 26: Storage limit max"

AUDIT_DIR=$(mktemp -d)
LOG_FILE="test_storage_log.txt"
STORAGE_LIMIT_MB=1

rm -f "$LOG_FILE"

dd if=/dev/zero of="$AUDIT_DIR/large_file" bs=1M count=2 status=none

check_storage 2> storage_warning.txt

if grep -q "\[WARNING\] Audit storage limit reached" storage_warning.txt && grep -q "\[WARNING\]" "$LOG_FILE"; then
	echo "[PASSED] Storage warning was displayed successfully!"
else
	echo "[FAILED] Storage warning was not displayed!"
	((FAILURES+=1))

fi

rm -rf "$AUDIT_DIR" "$LOG_FILE" storage_warning.txt

# Test 27: Checking if the audit directory is missing

echo ""
echo "Test 27: Missing audit directory"

AUDIT_DIR="/tmp/nonexistent_sysaudit_test"
LOG_FILE="test_storage_log.txt"
STORAGE_LIMIT_MB=1

rm -rf "$AUDIT_DIR" "$LOG_FILE"

check_storage 2> storage_error.txt
result=$?

if [[ "$result" -eq 1 ]] && grep -q "Audit directory does not exist" "$LOG_FILE"; then
	echo "[PASSED] Missing audit directory was handled successfully!"
else
	echo "[FAILED] Missing audit directory test has failed!"
	((FAILURES+=1))

fi

rm -f "$LOG_FILE" storage_error.txt

#Test 28: Testing if it rejects a storage limit for example 0

echo ""
echo "Test 28: Invalid Storage Limit"

AUDIT_DIR=$(mktemp -d)
LOG_FILE="test_storage_log.txt"
STORAGE_LIMIT_MB=0

rm -f "$LOG_FILE"

check_storage
result=$?

if [[ "$result" -eq 1 ]] && grep -q "Invalid storage limit" "$LOG_FILE"; then
	echo "[PASSED] Invalid storage limit was rejected!"
else
	echo "[FAILED] Invalid storage limit test has failed!"
	((FAILURES+=1))

fi

rm -rf "$AUDIT_DIR" "$LOG_FILE"

#Test 29: Testing unauthorized access from a user

echo ""
echo "Test 29: Unauthorized User Access"

bash sysaudit.sh --scan-interval 60
result=$?

if [[ "$result" -eq 2 ]]; then
	echo "[PASSED] Unauthorized user was denied!"
else
	echo "[FAILED] Unauthorized user test failed!"
	((FAILURES+=1))

fi

echo ""
echo "----------------------------"
echo "Test Summary:"
echo "----------------------------"

if [[ "$FAILURES" -eq 0 ]]; then
	echo "[SUCCESS] All 29 tests have passed!"
	exit 0
else
	echo "[FAILED] $FAILURES test(s) failed!"
	exit 1

fi
