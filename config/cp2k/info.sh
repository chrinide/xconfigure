#!/bin/bash
#############################################################################
# Copyright (c) 2016-2018, Intel Corporation                                #
# All rights reserved.                                                      #
#                                                                           #
# Redistribution and use in source and binary forms, with or without        #
# modification, are permitted provided that the following conditions        #
# are met:                                                                  #
# 1. Redistributions of source code must retain the above copyright         #
#    notice, this list of conditions and the following disclaimer.          #
# 2. Redistributions in binary form must reproduce the above copyright      #
#    notice, this list of conditions and the following disclaimer in the    #
#    documentation and/or other materials provided with the distribution.   #
# 3. Neither the name of the copyright holder nor the names of its          #
#    contributors may be used to endorse or promote products derived        #
#    from this software without specific prior written permission.          #
#                                                                           #
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS       #
# "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT         #
# LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR     #
# A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT      #
# HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,    #
# SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED  #
# TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR    #
# PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF    #
# LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING      #
# NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS        #
# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.              #
#############################################################################
# Hans Pabst (Intel Corp.)
#############################################################################

HERE=$(cd $(dirname $0); pwd -P)

BC=$(which bc 2> /dev/null)
PATTERN="*.txt"

BEST=0
if [ "-best" = "$1" ]; then
  SORT="sort -k2,2n -k6,6n | sort -u -k2,2n"
  BEST=1
  shift
else
  SORT="sort -k2,2n -k6,6n"
fi

if [ "" != "$1" ] && [ -e $1 ]; then
  FILEPATH="$1"
  shift
else
  FILEPATH="."
fi

NUMFILES=$(find ${FILEPATH} -maxdepth 1 -type f -name "${PATTERN}" | wc -l)
if [ "0" = "${NUMFILES}" ]; then
  PATTERN="*"
fi

FILES=$(find ${FILEPATH} -maxdepth 1 -type f -name "${PATTERN}")
FILE0=$(echo "${FILES}" | head -n1)
PRINTFLOPS=0
NUMFILES=0
if [ "" != "${FILE0}" ]; then
  NUMFILES=$(echo "${FILES}" | wc -l)
  PROJECT=$(grep "GLOBAL| Project name" ${FILE0} | sed -n "s/..*\s\s*\(\w\)/\1/p" | head -n1)
  if [ "PROJECT" = "${PROJECT}" ]; then
    PROJECT=$(grep "GLOBAL| Method name" ${FILE0} | sed -n "s/..*\s\s*\(\w\)/\1/p" | head -n1)
  fi
  if [ "" != "${BC}" ]; then
    if [ "LIBTEST" = "${PROJECT}" ] || [ "TEST" = "${PROJECT}" ]; then
      PRINTFLOPS=1
    fi
  fi
  echo -e -n "$(printf %-23.23s ${PROJECT})\tNodes\tR/N\tT/R\tCases/d\tSeconds"
  if [ "0" != "${PRINTFLOPS}" ]; then
    echo -e -n "\tGFLOPS/s"
  fi
  echo
fi

for FILE in ${FILES}; do
  BASENAME=$(basename ${FILE})
  NAME=$(echo ${BASENAME} | cut -d. -f1)
  NODERANKS=$(grep "^mpirun" ${FILE} | grep "\-np" | sed -n "s/..*-np\s\s*\([^\s][^\s]*\).*/\1/p" | cut -d" " -f1)
  RANKS=$(grep "^mpirun" ${FILE} | grep "\-perhost" | sed -n "s/..*-perhost\s\s*\([^\s][^\s]*\).*/\1/p" | cut -d" " -f1 | tr -d -c [:digit:])
  if [ "" = "${RANKS}" ]; then
    RANKS=$(grep "GLOBAL| Total number of message passing processes" ${FILE} | grep -m1 -o "[0-9][0-9]*")
    if [ "" = "${RANKS}" ]; then RANKS=1; fi
  fi
  if [ "" = "${NODERANKS}" ]; then
    NODES=$(echo ${BASENAME} | tr -s -c [:digit:] "-" | cut -d- -f1 | sed -e "s/0*\([1-9][0-9]*\).*/\1/")
    if [ "" = "${NODES}" ]; then
      NODES=$(echo ${BASENAME} | tr -s -c [:digit:] "-" | cut -d- -f2 | sed -e "s/0*\([1-9][0-9]*\).*/\1/")
    fi
    NODERANKS=${RANKS}
    if [ "" != "${NODES}" ] && [ "0" != "$((NODES<=NODERANKS))" ]; then
      RANKS=$((NODERANKS/NODES))
    fi
  fi
  if [ "" != "${NODERANKS}" ] && [ "" != "${RANKS}" ] && [ "0" != "${RANKS}" ]; then
    NODES=$((NODERANKS/RANKS))
    TPERR=$(grep OMP_NUM_THREADS ${FILE} | sed -n "s/.*\sOMP_NUM_THREADS=\([0-9][0-9]*\)\s.*/\1/p")
    if [ "" = "${TPERR}" ]; then
      TPERR=$(grep "GLOBAL| Number of threads for this process" ${FILE} | grep -m1 -o "[0-9][0-9]*")
      if [ "" = "${TPERR}" ]; then TPERR=1; fi
    fi
    DURATION=$(grep "CP2K                                 1" ${FILE} | tr -s " " | cut -d" " -f7)
    TWALL=$(echo ${DURATION} | cut -d. -f1 | sed -n "s/\([0-9][0-9]*\)/\1/p")
    if [ "" != "${TWALL}" ] && [ "0" != "${TWALL}" ]; then
      echo -e -n "$(printf %-23.23s ${NAME})\t${NODES}\t${RANKS}\t${TPERR}"
      echo -e -n "\t$((86400/TWALL))\t${DURATION}"
      if [ "0" != "${PRINTFLOPS}" ]; then
        FLOPS=$(sed -n "s/ marketing flops\s\s*\(..*\)$/\1/p" ${FILE} | sed -e "s/[eE]+*/\*10\^/")
        TBCSR=$(sed -n "s/ dbcsr_multiply_generic\s\s*\(..*\)$/\1/p" ${FILE} | tr -s " " | rev | cut -d" " -f1 | rev)
        if [ "" != "${FLOPS}" ] && [ "" != "${TBCSR}" ]; then
          GFLOPS=$(echo "scale=3;((${FLOPS})/(${TBCSR}*10^9))" | ${BC})
          echo -e -n "\t${GFLOPS}"
        fi
      fi
      echo
    elif [ "0" != "${NUMFILES}" ] && [ "0" = "${BEST}" ]; then
      echo -e -n "$(printf %-23.23s ${NAME})\t${NODES}\t${RANKS}\t${TPERR}"
      echo -e -n "\t0\t-"
      echo
    fi
  fi
done | eval ${SORT}

