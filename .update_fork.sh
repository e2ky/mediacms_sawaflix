#!/bin/bash

git fetch upstream &
jobs -l
wait
git checkout main
jobs -l
wait
git merge upstream/main
jobs -l
wait 		
