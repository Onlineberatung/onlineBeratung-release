#!/bin/bash

# ToDo's
# Validate t by YYYY-mm-dd
# Merge REPOS and RELEASE_BY_BRANCH in assoc array or get rid of it ;-)
# Optimize clone/checkout by shallow copy

RED='\033[0;31m'
GREEN='\033[0;32m'
ORANGE='\033[0;33m'
BLUE='\033[0;36m'
NC='\033[0m'

INFO="${BLUE}[INFO]${NC}"
ERROR="${RED}[ERRO]${NC}"
NOTICE="${ORANGE}[NOTE]${NC}"
SUCCESS="${GREEN}[SUCC]${NC}"

CLONE_DIR="./repositories"
declare -A RELEASEBRANCHES=(
  [staging]=develop
  [release]=staging
)

AVAILABLE_BRANCHES=$(printf ", %s" "${!RELEASEBRANCHES[@]}")
AVAILABLE_BRANCHES=${AVAILABLE_BRANCHES:2}

if [ -f .env ]
then
  export $(grep -v '^#' .env | xargs)
fi

PREREQUISITE=(
  "git"
)

###########################
### Check prerequisites ###
###########################
echo -e "${INFO} Checking prerequisites ..."
for i in "${PREREQUISITE[@]}"
do
	if ! command -v "${i}" &> /dev/null
  then
      echo -e "${ERROR} $i needs to be installed!"
      exit 1
  fi
done
echo -e "${SUCCESS} Prerequisites met!"

### Check for git cli installation
ghAvailable=0
if command -v gh &> /dev/null
then
    ghAvailable=1
fi

#######################
### Check arguments ###
#######################
AUTO_MERGE=0
VERBOSE=0
INIT_RELEASE_BRANCH=0
BRANCH=
TAG=
GH_TOKEN_OVERRIDE=
usage() { echo "Usage: $0 -b <${AVAILABLE_BRANCHES}> -t <2022-12-14> [-g <GH_TOKEN>] [-mhvi]" 1>&2; exit 1; }
while getopts ":mb:t:g:hvi" o; do
    case "${o}" in
        m)
            AUTO_MERGE=1
            ;;
        b)
            BRANCH=${OPTARG}
            ;;
        t)
            TAG=${OPTARG}
            ;;
        v)
            VERBOSE=1
            ;;
        i)
            INIT_RELEASE_BRANCH=1
            ;;
        g)
            GH_TOKEN_OVERRIDE=${OPTARG}
            ;;
        *)
            usage
            ;;
    esac
done
shift $((OPTIND-1))

if [ -z "$BRANCH" ]; then
  echo -e "${ERROR} Please provide release branch as argument [${AVAILABLE_BRANCHES}]";
  exit 1;
else
  if ! [ ${RELEASEBRANCHES[$BRANCH]+_} ]; then
    echo -e "${ERROR} Please provide a valid release branch! [${AVAILABLE_BRANCHES}]";
    exit 1
  else
    echo -e "${NOTICE} Defined branch to release: $BRANCH";
  fi
fi

if [ -z "$TAG" ]; then
  echo -e "${ERROR} Please provide release date [e.g.: 2022-12-14]";
  exit 1;
else
  echo -e "${NOTICE} Defined release date: $TAG";
fi

if [ -z "$GH_TOKEN_OVERRIDE" ] && [ -z "$GH_TOKEN" ] && [ $ghAvailable = 1 ] ; then
  echo -e "${ERROR} Please provide set your github token in .env or pass it as third parameter to the command";
  exit 1;
elif [ $ghAvailable = 1 ] && [ -z "$GH_TOKEN" ] ; then
   export GH_TOKEN=$GH_TOKEN_OVERRIDE
fi

if [ $AUTO_MERGE = 1 ] ; then
  read -p "Auto merge is enabled! Are you sure you want proceed? [y/N]" -n 1 -r
  echo    # (optional) move to a new line
  if [[ ! $REPLY =~ ^[Yy]$ ]]
  then
      echo -e "${NOTICE} Script canceled!"
      exit 1
  fi
fi

if ! [ -f repos.txt ] ; then
      echo -e "${ERROR} Repos file (repos.txt) not found!"
      exit 1
fi

readarray -t REPOS < ./repos.txt

for i in "${!REPOS[@]}"; do
  [ -n "${REPOS[$i]}" ] || unset "REPOS[$i]"
done

if [ ${#REPOS[@]} -eq 0 ] ; then
      echo -e "${ERROR} Repos file contains no repositories!"
      exit 1
fi

echo -e "${SUCCESS} SUCCESS"
exit

##############################
### Create clone directory ###
##############################
echo -e "${INFO} Create clone directory ${CLONE_DIR} ..."
mkdir "${CLONE_DIR}" 2>/dev/null
if ! cd "${CLONE_DIR}" 2>/dev/null ; then
    echo -e "${ERROR} Change directory to ${CLONE_DIR} failed"
    exit 1
fi
echo -e "${SUCCESS} Directory created!"

##########################
### Clone repositories ###
##########################
declare -A REPO_DIRS
echo -e "${INFO} Cloning repositories ..."
for REPO_NAME in "${REPOS[@]}"
do
  if git clone "git@github.com:${REPO_NAME}.git" 2>/dev/null ; then
      if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Cloned: ${REPO_NAME}"; fi
  fi
  IFS='/' read -r -a REPO_PARTS <<< "$REPO_NAME"
  REPO_DIRS["${REPO_NAME}"]="${REPO_PARTS[1]}"
done
echo -e "${SUCCESS} Repositories cloned!"

################################
### Check clean repositories ###
################################
echo -e "${INFO} Checking repositories for unstaged or uncommited changes ..."
err=0
for REPO_NAME in "${REPOS[@]}"
do
  REPO_DIR="${REPO_DIRS[$REPO_NAME]}"

  if ! cd "${REPO_DIR}" 2>/dev/null ; then
      echo -e "${ERROR} Change directory to ${REPO_DIR} failed"
      exit 1
  fi

  if [[ -n $(git status -s) ]] ; then
      echo -e >&2 "${ERROR} Repository ${REPO_DIR} has unstaged or uncommited changes!"
      err=1
  fi

  cd ..
done

if [ $err = 1 ] ; then
    echo -e >&2 "${ERROR} Please commit or stash them."
    exit 1
else
  echo -e "${SUCCESS} All repositories clean"
fi

######################################################
### Update branches and checkout branch to release ###
######################################################
echo -e "${INFO} Prepare branch and update release branch ..."
err=0
for REPO_NAME in "${REPOS[@]}"
do
  REPO_DIR="${REPO_DIRS[$REPO_NAME]}"

  if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Updating: ${REPO_NAME}"; fi

  if ! cd "${REPO_DIR}" 2>/dev/null ; then
      echo -e "${ERROR} Change directory to ${REPO_DIR} failed"
      exit 1
  fi

  if ! git fetch -q --all 2>/dev/null ; then
      echo -e "${ERROR} Fetch repositories failed!"
      err=1
      break
  fi

  if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Updating: ${RELEASEBRANCHES[$BRANCH]}"; fi
  if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Checkout: ${RELEASEBRANCHES[$BRANCH]}"; fi
  if ! git checkout -q "${RELEASEBRANCHES[$BRANCH]}" 2>/dev/null ; then
      echo -e "${ERROR} Failed!"
      err=1
      break
  fi
  if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Pull: ${RELEASEBRANCHES[$BRANCH]}"; fi
  if ! git pull -q 2>/dev/null ; then
      echo -e "${ERROR} Failed!"
      err=1
      break
  fi

  if git ls-remote -q --exit-code --heads origin "${BRANCH}" 2>/dev/null 1>/dev/null ; then
    if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Updating: ${BRANCH}"; fi
    if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Checkout: ${BRANCH}"; fi
    if ! git checkout -q "${BRANCH}" 2>/dev/null ; then
        echo -e "${ERROR} Failed!"
        err=1
        break
    fi
    if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Pull: ${BRANCH}"; fi
    if ! git pull -q 2>/dev/null ; then
        echo -e "${ERROR} Failed!"
        err=1
        break
    fi
  else
    if [ $INIT_RELEASE_BRANCH = 0 ] ; then
      echo -e "${ERROR} Branch release not found on remote! Create it on github or pass -i to create it!"
      err=1
      break
    fi

    echo -e "${INFO} Init release branch ${BRANCH}";
    if ! git checkout -b "${BRANCH}" 2>/dev/null ; then
       echo -e "${ERROR} Can't create local branch ${BRANCH}!"
       err=1
       break
    fi

    if ! git push -q --set-upstream origin "${BRANCH}" 2>/dev/null ; then
        echo -e "${ERROR} Pushing ${BRANCH} failed!"
        err=1
        break
    fi

    echo -e "${NOTICE} ATTENTION! Please protect the new release branch on github!";
  fi

  cd ..
done

if [ $err = 1 ] ; then
    echo -e >&2 "${ERROR} Could not update all repositories!"
    exit 1
else
  echo -e "${SUCCESS} All repositories updated"
fi

#######################################
### Create or update release branch ###
#######################################
declare -A REPO_RELEASE_BRANCHES
echo -e "${INFO} Prepare branch and update release branch ..."
err=0
for REPO_NAME in "${REPOS[@]}"
do
  REPO_DIR="${REPO_DIRS[$REPO_NAME]}"

  if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Prepare: ${REPO_NAME}"; fi

  if ! cd "${REPO_DIR}" 2>/dev/null ; then
      echo -e "${ERROR} Change directory to ${REPO_DIR} failed"
      exit 1
  fi

  diffLines=$( git diff --name-only "${BRANCH}".."${RELEASEBRANCHES[$BRANCH]}" | wc -l )
  if ! [ "${diffLines}" -gt 0 ] ; then
      echo -e "${INFO} Repository has not changes between ${BRANCH} and ${RELEASEBRANCHES[$BRANCH]}. Skipping!"
      cd ..
      continue
  else
    if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Repository ${REPO_NAME} has ${diffLines} changed files between ${BRANCH} and ${RELEASEBRANCHES[$BRANCH]}."; fi
  fi

  RELEASE_BRANCH="${BRANCH}-${TAG}"

  if git ls-remote -q --exit-code --heads origin "${RELEASE_BRANCH}" 2>/dev/null 1>/dev/null ; then
    if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Updating remote release branch ${RELEASE_BRANCH}"; fi
    if ! git checkout "${RELEASE_BRANCH}" 2>/dev/null ; then
       echo -e "${ERROR} Can't checkout remote branch ${RELEASE_BRANCH}!"
       err=1
       break
    fi
    git pull -q 2>/dev/null
  else
    if [[ $(git branch -q -l "${RELEASE_BRANCH}" | wc -l) -ne 0 ]]; then
      if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Updating local release branch ${RELEASE_BRANCH}"; fi
      if ! git checkout "${RELEASE_BRANCH}" 2>/dev/null ; then
         echo -e "${ERROR} Can't checkout local branch ${RELEASE_BRANCH}!"
         err=1
         break
      fi
    else
      if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Creating new release branch ${RELEASE_BRANCH}"; fi
      if ! git checkout -b "${RELEASE_BRANCH}" 2>/dev/null ; then
         echo -e "${ERROR} Can't create local branch ${RELEASE_BRANCH}!"
         err=1
         break
      fi
    fi
  fi

  if ! git merge --no-edit --auto -q "${RELEASEBRANCHES[$BRANCH]}" 2>/dev/null ; then
      echo -e "${ERROR} Merging ${RELEASEBRANCHES[$BRANCH]} into ${RELEASE_BRANCH} failed!"
      err=1
      break
  fi

  REPO_RELEASE_BRANCHES["${REPO_NAME}"]="${RELEASE_BRANCH}"

  cd ..
done

if [ $err = 1 ] ; then
    echo -e >&2 "${ERROR} Could not create a release branch for all repositories!"
    exit 1
else
  echo -e "${SUCCESS} All repositories have been merged"
fi

#############################
### Push release branches ###
#############################

echo -e "${INFO} Push release branches to github ..."
err=0
for REPO_NAME in "${REPOS[@]}"
do
  REPO_DIR="${REPO_DIRS[$REPO_NAME]}"

  if ! [ ${REPO_RELEASE_BRANCHES[$REPO_NAME]+_} ]; then
    continue
  fi

  echo -e "${INFO} Push release branch ${REPO_RELEASE_BRANCHES[$REPO_NAME]} to ${REPO_NAME}"

  if ! cd "${REPO_DIR}" 2>/dev/null ; then
      echo -e "${ERROR} Change directory to ${REPO_NAME} failed"
      exit 1
  fi

  if ! git push -q --set-upstream origin "${RELEASE_BRANCH}" 2>/dev/null ; then
      echo -e "${ERROR} Pushing ${RELEASE_BRANCH} failed!"
      err=1
      break
  fi

  cd ..
done

if [ $err = 1 ] ; then
    echo -e >&2 "${ERROR} Could not push release branch for all repositories!"
    exit 1
else
  echo -e "${SUCCESS} All repositories have been pushed"
fi

#################################################
### Create pull requests for release branches ###
#################################################

PRS_TO_CREATE=()
PRS_TO_APPROVE=()

if [ $ghAvailable = 0 ] ; then
    echo -e "${NOTICE} 'gh' is not installed! You need to open the pull requests manually by using the following links!"
    echo -e "${INFO} Create links to open pull requests ..."
else
    echo -e "${INFO} Create pull requests for release branches ..."
fi

for REPO_NAME in "${REPOS[@]}"
do
  REPO_DIR="${REPO_DIRS[$REPO_NAME]}"

  if ! [ ${REPO_RELEASE_BRANCHES[$REPO_NAME]+_} ]; then
    continue
  fi

  PR_URL="https://github.com/${REPO_NAME}/compare/${BRANCH}...${REPO_NAME//\//:}:${REPO_RELEASE_BRANCHES[$REPO_NAME]}"
  # If gh is not installed just show urls to open the pull requests
  if [ $ghAvailable = 0 ] ; then
      PRS_TO_CREATE+=("${PR_URL}")
      continue
  fi

  if [ $VERBOSE = 1 ] ; then echo -e "${INFO} Create pull request for release branch ${REPO_RELEASE_BRANCHES[$REPO_NAME]} on ${REPO_NAME}"; fi

  if ! cd "${REPO_DIR}" 2>/dev/null ; then
      echo -e "${ERROR} Change directory to ${REPO_NAME} failed"
      exit 1
  fi

  PR_URL=$(gh pr create --base "${BRANCH}" --title="${BRANCH} ${TAG}" --body="Some body" --repo "${REPO_NAME}" 2>&1 | grep "https://github.com")
  PRS_TO_APPROVE+=("${PR_URL}")

  cd ..
done

if [ $ghAvailable = 0 ] ; then
  echo -e "${SUCCESS} Links created"
else
  echo -e "${SUCCESS} Pull requests created"
fi

if [ "${#PRS_TO_CREATE[@]}" -gt 0 ] ; then
  echo ""
  echo -e "${NOTICE} Please create the following ${#PRS_TO_CREATE[@]} pull request(s):"
  for PR_TO_CREATE in "${PRS_TO_CREATE[@]}"
  do
    echo -e "- ${PR_TO_CREATE}"
  done
fi

if [ "${#PRS_TO_APPROVE[@]}" -gt 0 ] ; then
  echo ""
  if [ $AUTO_MERGE = 1 ] ; then
    echo -e "${NOTICE} Try to merge ${#PRS_TO_APPROVE[@]} pull request(s):"
    for PR_TO_APPROVE in "${PRS_TO_APPROVE[@]}"
    do
      if ! gh pr merge --auto -m "${PR_TO_APPROVE}" 2>/dev/null ; then
        echo -e "${ERROR} Auto merge ${PR_TO_APPROVE} failed"
        continue
      fi

      echo -e "${SUCCESS} Auto merged ${PR_TO_APPROVE}"
    done
  else
    echo -e "${NOTICE} Please approve the following ${#PRS_TO_APPROVE[@]} pull request(s):"
    for PR_TO_APPROVE in "${PRS_TO_APPROVE[@]}"
    do
      echo -e "- ${PR_TO_APPROVE}"
    done

    if [[ -n $TEAMS_WEBHOOK_URL ]] ; then
      MESSAGE="**A new release to ${BRANCH} has been made.** <br/>"
      MESSAGE+="--------- <br/>"
      MESSAGE+="The following pull requests needs to be approved: <br/>"

      MESSAGE+="<ul>"
      for PR_TO_APPROVE in "${PRS_TO_APPROVE[@]}"
      do
        MESSAGE+="<li>${PR_TO_APPROVE}</li>"
      done
      MESSAGE+="</ul>"
      curl -H 'Content-Type: application/json' -d "{\"text\": \"${MESSAGE}\"}" "${TEAMS_WEBHOOK_URL}" 2>/dev/null 1>/dev/null
    fi
  fi
fi

echo ""
echo -e "${SUCCESS} Everything done!"
exit 0

