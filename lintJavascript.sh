#!/bin/sh

EXTENSIONS_TO_LINT=('js' 'conf') && declare -a DIFF_BEFORE_LINT FILES_TO_LINT SKIPPED_FILES WARNINGS LINTED_FILES
GIT_DIFF () { # git diff on staged files
	git diff --cached $1 $2
}
CHECK_CHANGE_TYPE () { # check change type of staged files
	git diff --cached --name-status | awk NR==$1 | awk '{print substr ($0, 0, 1)}'
}
CHECK_FILE_EXTENSION () { # check staged file extensions
	git diff --cached --name-only | awk NR==$1 | awk 'BEGIN { FS = "." } ; { print $2 }'
}
AWK_REMOVE_SPACE () { # AWK space delimeter
	awk '{ gsub (" ", "", $0); print}'
}
GIT_DIFF_STAT () { # git diff stats on staged files
	git diff --stat --cached $1 | awk -F\| '{ print $2 }' | AWK_REMOVE_SPACE
}
IS_VALID_LINTING_FILE () { # check if file is valid for linting
	for ignoredExtension in $@ ; do
		if [ `CHECK_FILE_EXTENSION $1` = $ignoredExtension ] ; then echo 0 ; fi
	done
}
SORT_LINTING_CHANGES () { # sort files after lint between LINTED_FILES & WARNINGS
	ITERATION=0 && local expanded_array="$1[@]"
	for file in ${!expanded_array} ; do
		if [[ ${DIFF_BEFORE_LINT[$ITERATION]} != `GIT_DIFF_STAT $file` ]] ; then THIS_STAT=$(GIT_DIFF_STAT $file)
			if [[ ${#THIS_STAT} != 0 ]] ; then LINTED_FILES+=($file)
			else WARNINGS+=($file) ; fi
		fi ; ITERATION=$(( $ITERATION + 1 ))
	done
}
REPORT_LINTING_CHANGES () { # report the changes applied to fixes, warnings, and skipped files
	ITERATION=0 && local expanded_array="$3[@]"
	if [[ $1 != 0 ]] ; then echo $2 && echo
		for file in ${!expanded_array} ; do THIS_CHANGE=$(GIT_DIFF --name-status $file | awk '{print substr ($0, 0, 1)}') && THIS_STAT=$(GIT_DIFF_STAT $file)
			if [[ $4 = "fix" ]] ; then OUTPUT="\x1B[32;1m$THIS_CHANGE\x1B[0;32m $file\x1B[0m: $5( ${DIFF_BEFORE_LINT[$ITERATION]} ) --> ( $THIS_STAT )" ; fi
			if [[ $4 = "skip" ]] ; then OUTPUT="\x1B[90;1m$THIS_CHANGE\x1B[0;90m $file\x1B[0m: $5" ; fi
			if [[ $4 = "warning" ]] ; then OUTPUT="\x1B[1m$file\x1b[0m" ; fi
			echo "   $OUTPUT" && ITERATION=$(( $ITERATION + 1 ))
		done
	echo
	fi
}
NUM_STAGED_FILES=$(GIT_DIFF --name-only | wc -l)
if [[ $NUM_STAGED_FILES -gt 0 ]] ; then ITERATION=0 # check staged files for proper extensions, store git diff before fixes and store skipped files
    while [ $ITERATION -lt $NUM_STAGED_FILES ] ; do ITERATION=$(( $ITERATION + 1 ))
        if [ `CHECK_CHANGE_TYPE $ITERATION` != 'D' ] ; then
            if [[ `IS_VALID_LINTING_FILE $ITERATION ${EXTENSIONS_TO_LINT[@]}` = 0 ]] ; then
			  DIFF_BEFORE_LINT+=($(GIT_DIFF_STAT $(GIT_DIFF --name-only | awk NR==$ITERATION))) && FILES_TO_LINT+=(`GIT_DIFF --name-only | awk NR==$ITERATION`)
            else SKIPPED_FILES+=(`GIT_DIFF --name-only | awk NR==$ITERATION`) ; fi
        fi
    done # run eslint, apply fixes and report status
	CAUGHT_LINT_ERROR=false && RAN_LINTER=true
    if [ ${#FILES_TO_LINT[@]} != 0 ] ; then npx eslint --fix --fix-type layout ${FILES_TO_LINT[*]} 
        if [ $? != 0 ] ; then CAUGHT_LINT_ERROR=true ; fi
        git add ${FILES_TO_LINT[*]} && SORT_LINTING_CHANGES FILES_TO_LINT
	else echo && echo " no staged files were linted"
    fi
	if [ "$RAN_LINTER" = true ] ; then echo "\x1B[1;35meslint $(npx eslint -v):\x1B[0m" && echo
		REPORT_LINTING_CHANGES ${#LINTED_FILES[@]} " \x1B[1m   applied fixes to files\x1B[0m:" LINTED_FILES "fix"
		REPORT_LINTING_CHANGES ${#SKIPPED_FILES[@]} " \x1B[1m   skipped files\x1B[0m:" SKIPPED_FILES "skip" " skipped non .js file "
		REPORT_LINTING_CHANGES ${#WARNINGS[@]} " \x1B[33;1;2m   WARNING\x1B[0m: changes to the following files have been reverted by precommit:" WARNINGS "warning"
		if [ "$CAUGHT_LINT_ERROR" = true ] ; then echo '\x1b[31;1mcommit failed \x1B[0;31m- correct the above linting errors before commiting\x1b[0m'
			exit 1 # if eslint exits with non-zero code then stop the commit
		fi
	fi
else echo "  no files are staged for linting" && echo ; fi
exit 0
