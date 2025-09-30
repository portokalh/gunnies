#! /bin/bash


## 15 June 2020, BJA: I still need to figure out the best way to pull out the non-zero bval(s) from the bval file.
## For now, hardcoding it to 1000 to run Whitson data. # 8 September 2020, BJA: changing to 800 for Sinha data.
## 24 January 2022, BJA: Changing bval to 2400 for Manisha's data.
## 21 January 2025, BJA: Totally rewrote based around chatGPT's answer when asking how to preprocess using MRtrix

# Will try to auto-extract bval going forward...though it is not yet designed to handle multi-shell acquisitions.
#nominal_bval='2000';

#GD=${GUNNIES}
#if [[ ! -d ${GD} ]];then
#	echo "env variable '$GUNNIES' not defined...failing now..."  && exit 1
#fi

project=ADRC


# ====== HELPERS (auto-added) ======
json_for() {
  local nii="$1"; local base="${nii%.gz}"; base="${base%.nii}"
  local j1="${base}.json"
  [[ -f "$j1" ]] && { echo "$j1"; return 0; }
  local jalt; jalt=$(ls -1 "${base}"*.json 2>/dev/null | head -n1 || true)
  [[ -n "$jalt" ]] && { echo "$jalt"; return 0; }
  return 1
}
pe_bids_to_mrtrix() {
  case "$1" in
    i)  echo "LR" ;; i-) echo "RL" ;;
    j)  echo "PA" ;; j-) echo "AP" ;;
    k)  echo "IS" ;; k-) echo "SI" ;;
    *)  echo ""   ;;
  esac
}
readout_from_json() {
  local j="$1"
  local trt; trt=$(jq -r '."TotalReadoutTime" // empty' "$j" 2>/dev/null)
  if [[ -n "$trt" && "$trt" != "null" ]]; then echo "$trt"; return 0; fi
  local ees rpe ape
  ees=$(jq -r '."EffectiveEchoSpacing" // ."DerivedVendorReportedEchoSpacing" // empty' "$j" 2>/dev/null)
  rpe=$(jq -r '."ReconMatrixPE" // empty' "$j" 2>/dev/null)
  ape=$(jq -r '."AcquisitionMatrixPE" // empty' "$j" 2>/dev/null)
  if [[ -n "$ees" && "$ees" != "null" ]]; then
    if [[ -n "$rpe" && "$rpe" != "null" ]]; then awk -v ees="$ees" -v n="$rpe" 'BEGIN{printf "%.6f", ees*(n-1)}'; echo; return 0; fi
    if [[ -n "$ape" && "$ape" != "null" ]]; then awk -v ees="$ees" -v n="$ape" 'BEGIN{printf "%.6f", ees*(n-1)}'; echo; return 0; fi
  fi
  echo ""
}
opposite_of() {
  case "$1" in
    AP) echo "PA" ;; PA) echo "AP" ;;
    RL) echo "LR" ;; LR) echo "RL" ;;
    IS) echo "SI" ;; SI) echo "IS" ;;
    *)  echo ""   ;;
  esac
}
run_extractdiffdirs() {
  local bxh_file="$1"; local out_prefix="$2"
  local remote_host="${REMOTE_HOST:-andros}"
  local remote_opts="${SSH_OPTS:--o BatchMode=yes -o ConnectTimeout=6}"
  local need_scp="${REMOTE_SCP:-auto}"  # auto|on|off

  [[ -f "$bxh_file" ]] || { echo "[ERR] BXH not found: $bxh_file"; return 2; }
  [[ -n "$out_prefix" ]] || { echo "[ERR] Missing out_prefix"; return 2; }
  local out_dir; out_dir="$(dirname "$out_prefix")"; local out_base; out_base="$(basename "$out_prefix")"; mkdir -p "$out_dir"

  # Prefer the system wrapper we created (venv) over ~/.local/bin
  local EXTRACT_BIN=""
  if [[ -x /usr/local/bin/extractdiffdirs ]]; then
    EXTRACT_BIN=/usr/local/bin/extractdiffdirs
  elif command -v extractdiffdirs >/dev/null 2>&1; then
    EXTRACT_BIN="$(command -v extractdiffdirs)"
# (auto-removed stray)   fi

  # --- Try LOCAL first -------------------------------------------------------
  if [[ -n "$EXTRACT_BIN" ]]; then
    echo "[BXH] Local: $EXTRACT_BIN --rowvectors"
    # rowvectors → FSL-style 3-row bvecs
    if "$EXTRACT_BIN" "$bxh_file" "$out_prefix" --rowvectors; then
      if [[ -s "${out_prefix}.bvec" && -s "${out_prefix}.bval" ]]; then
        echo "[BXH] OK (local, rowvectors)"
        return 0
# (auto-removed stray)       fi
      echo "[BXH] Local rowvectors ran but outputs missing → will try colvectors"
    else
      echo "[BXH] Local rowvectors failed → will try colvectors"
# (auto-removed stray)     fi

    echo "[BXH] Local: $EXTRACT_BIN --colvectors (then transpose to rows)"
    if "$EXTRACT_BIN" "$bxh_file" "$out_prefix" --colvectors; then
      # Transpose to 3 rows if needed (col-vectors -> row-vectors)
      if [[ -s "${out_prefix}.bvec" ]]; then
        awk '
          { for (i=1; i<=NF; i++) a[NR,i]=$i }
          NF>p { p = NF }
          END{
            for (j=1; j<=p; j++) {
              out=""
              for (i=1; i<=NR; i++) {
                out = out (i==1? "": " ") a[i,j]
              }
              print out
            }
          }
        ' "${out_prefix}.bvec" > "${out_prefix}.bvec.tmp" && mv -f "${out_prefix}.bvec.tmp" "${out_prefix}.bvec"
# (auto-removed stray)       fi
      if [[ -s "${out_prefix}.bvec" && -s "${out_prefix}.bval" ]]; then
        echo "[BXH] OK (local, colvectors→transposed)"
        return 0
# (auto-removed stray)       fi
      echo "[BXH] Local colvectors ran but outputs missing."
    else
      echo "[BXH] Local colvectors failed."
# (auto-removed stray)     fi
  else
    echo "[BXH] extractdiffdirs not found locally."
# (auto-removed stray)   fi

  # --- Try REMOTE (ssh) ------------------------------------------------------
  if [[ "${ALLOW_SSH:-1}" -eq 1 ]]; then
    echo "[BXH] checking remote ${remote_host} …"
    if ssh $remote_opts "$remote_host" 'command -v extractdiffdirs >/dev/null 2>&1'; then
      echo "[BXH] Remote: extractdiffdirs --rowvectors"
      if ssh $remote_opts "$remote_host" "extractdiffdirs '$bxh_file' '$out_prefix' --rowvectors"; then
        if [[ -s "${out_prefix}.bvec" && -s "${out_prefix}.bval" ]]; then
          echo "[BXH] OK (remote, shared FS)"
          return 0
# (auto-removed stray)         fi
        if [[ "$need_scp" == "auto" || "$need_scp" == "on" ]]; then
          echo "[BXH] scp back results from ${remote_host}"
          scp $remote_opts "${remote_host}:${out_prefix}.bvec" "${out_dir}/${out_base}.bvec" || true
          scp $remote_opts "${remote_host}:${out_prefix}.bval" "${out_dir}/${out_base}.bval" || true
          [[ -s "${out_prefix}.bvec" && -s "${out_prefix}.bval" ]] && { echo "[BXH] OK (remote→scp)"; return 0; }
# (auto-removed stray)         fi
        echo "[BXH] Remote ran rowvectors, outputs not visible locally."
      else
        echo "[BXH] Remote rowvectors failed → try colvectors"
        ssh $remote_opts "$remote_host" "extractdiffdirs '$bxh_file' '$out_prefix' --colvectors" || true
        if [[ -s "${out_prefix}.bvec" && -s "${out_prefix}.bval" ]]; then
          # transpose if necessary
          awk '
            { for (i=1; i<=NF; i++) a[NR,i]=$i }
            NF>p { p = NF }
            END{
              for (j=1; j<=p; j++) {
                out=""
                for (i=1; i<=NR; i++) {
                  out = out (i==1? "": " ") a[i,j]
                }
                print out
              }
            }
          ' "${out_prefix}.bvec" > "${out_prefix}.bvec.tmp" && mv -f "${out_prefix}.bvec.tmp" "${out_prefix}.bvec"
          echo "[BXH] OK (remote, colvectors→transposed)"
          return 0
# (auto-removed stray)         fi
# (auto-removed stray)       fi
    else
      echo "[BXH] extractdiffdirs not available on ${remote_host} (or SSH failed)."
# (auto-removed stray)     fi
# (auto-removed stray)   fi

  return 4
}

resolve_grads() {
  local input_path="$1"; local target_bvec="$2"; local target_bval="$3"
  local main_nii="$input_path"
  local main_base="${main_nii%.gz}"; main_base="${main_base%.nii}"
  local src_bvec="${main_base}.bvec"; local src_bval="${main_base}.bval"
  if [[ -s "$src_bvec" && -s "$src_bval" ]]; then
    echo "[grads] sidecars found"; cp -f "$src_bvec" "$target_bvec"; cp -f "$src_bval" "$target_bval"; return 0
# (auto-removed stray)   fi
  echo "[auto] No .bvec/.bval next to ${main_nii}; trying BXH…"
  local bxh_file="${main_base}.bxh"
  if [[ ! -f "$bxh_file" ]]; then bxh_file="$(ls -1 "$(dirname "$main_nii")"/*.bxh 2>/dev/null | head -n1 || true)"; fi
  if [[ -z "$bxh_file" || ! -f "$bxh_file" ]]; then echo "[note] No BXH sibling for ${main_nii}"; return 1; fi
  run_extractdiffdirs "$bxh_file" "$main_base" || true
  if [[ -s "${main_base}.bvec" && -s "${main_base}.bval" ]]; then
    echo "[grads] extracted from BXH"; cp -f "${main_base}.bvec" "$target_bvec"; cp -f "${main_base}.bval" "$target_bval"; return 0
# (auto-removed stray)   fi
  echo "[warn] Unable to obtain gradients"; return 2
}
# ====== HELPERS (auto-added) ======

# Process name
proc_name="diffusion_prep_MRtrix"; # Not gonna call it diffusion_calc so we don't assume it does the same thing as the civm pipeline



if [[ -d ${GUNNIES} ]];then
	GD=${GUNNIES};
else
	GD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd );
# (auto-removed stray) fi

## Determine if we are running on a cluster--for now it is incorrectly assumed that all clusters are SGE clusters
cluster=$(bash cluster_test.bash);
if [[ $cluster ]];then
    if [[ ${cluster} -eq 1 ]];then
		sub_script=${GD}/submit_slurm_cluster_job.bash;
# (auto-removed stray) 	fi
    if [[ ${cluster} -eq 2 ]];then
		sub_script=${GD}/submit_sge_cluster_job.bash
# (auto-removed stray) 	fi
	echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
# (auto-removed stray) fi


BD=${BIGGUS_DISKUS}
if [[ ! -d ${BD} ]];then
	echo "env variable '$BIGGUS_DISKUS' not defined...failing now..."  && exit 1
# (auto-removed stray) fi

# This script is designed to be ran on human data, so let's be sneaky and ensure that it
# ends up in a 'human' directory instead of a 'mouse'

BD2=${BD%/}
mama_dir=${BD2%/*};
baby_dir=${BD2##*/};
if [[ 'xmousex' == "x${baby_dir}x" ]];then
	BD="${mama_dir}/human/";
	export BIGGUS_DISKUS=$BD;
	if [[ ! -d $BD ]];then
		mkdir -m 775 ${BD};
# (auto-removed stray) 	fi
# (auto-removed stray) fi


id=$1;
raw_nii=$2;
# === AUTO: folder input normalization (largest=main, second-largest=reverse) ===
if [[ -d "$raw_nii" ]]; then
  echo "[auto] Directory input: $raw_nii"
  mapfile -t _nii < <(find "$raw_nii" -maxdepth 1 -type f \( -iname "*.nii" -o -iname "*.nii.gz" \) \
                      -printf "%s\t%p\n" | sort -nr | awk 'NR<=2{print $2}')
  if [[ ${#_nii[@]} -lt 1 ]]; then echo "[ERR] No NIfTI files in $raw_nii"; exit 2; fi
  raw_nii="${_nii[0]}"
  revpe="${revpe:-${_nii[1]:-}}"
  echo "[auto] main DWI: $raw_nii"
  [[ -n "$revpe" ]] && echo "[auto] reverse: $revpe"
# (auto-removed stray) fi

no_cleanup=$3;

# --- folder→file normalization (must run BEFORE any Bvec/Bval logic) ---
if [[ -d "$raw_nii" ]]; then
  echo "[auto] Directory input: $raw_nii"
  mapfile -t _nii < <(find "$raw_nii" -maxdepth 1 -type f \( -iname "*.nii" -o -iname "*.nii.gz" \) \
                      -printf "%s\t%p\n" | sort -nr | awk 'NR<=2{print $2}')
  if [[ ${#_nii[@]} -lt 1 ]]; then
    echo "[ERR] No NIfTI files in $raw_nii"; exit 2
# (auto-removed stray)   fi
  # Largest → main; second largest → reverse (if present)
  raw_nii="${_nii[0]}"
  revpe="${_nii[1]:-}"
  echo "[auto] main DWI: $raw_nii"
  [[ -n "$revpe" ]] && echo "[auto] reverse: $revpe"
# (auto-removed stray) fi



if [[ "x1x" == "x${no_cleanup}x" ]];then
    cleanup=0;
else
    cleanup=1;
# (auto-removed stray) fi

echo "Processing diffusion data with runno/id: ${id}.";

# I think we should always use fsl...our home brewed coreg seems to be too loosy-goosy
use_fsl=1;
if ((${use_fsl}));then
	work_dir=${BD}/${proc_name}_${id};
else
	work_dir=${BD}/${proc_name}_with_coreg_${id};
# (auto-removed stray) fi
echo "Work directory: ${work_dir}";
if [[ ! -d ${work_dir} ]];then
    mkdir -pm 775 ${work_dir};
# (auto-removed stray) fi

sbatch_folder=${work_dir}/sbatch;
if [[ ! -d ${sbatch_folder} ]];then
    mkdir -pm 775 ${sbatch_folder};
# (auto-removed stray) fi

nii_name=${raw_nii##*/};
ext="nii.gz";

bxheader=${raw_nii/nii.gz/bxh}
#    echo "Input nifti = ${raw_nii}.";
#    echo "Input header = ${bxheader}.";

bvecs=${work_dir}/${id}_bvecs.txt;
bvals=${bvecs/bvecs/bvals};

echo "Bvecs: ${bvecs}";
# --- BEGIN robust gradients resolution for NIfTI / BXH (drop-in) ---
# main NIfTI chosen earlier (folder input logic set raw_nii)
main_nii="${raw_nii}"
main_base="${main_nii%.gz}"; main_base="${main_base%.nii}"

# default sources (if sidecars exist next to the NIfTI)
src_bvec="${main_base}.bvec"
src_bval="${main_base}.bval"

have_grads=0
if [[ -s "$src_bvec" && -s "$src_bval" ]]; then
  have_grads=1
else
  echo "[auto] No .bvec/.bval next to ${main_nii}; trying to extract from BXH…"
  # try BXH with the same stem first
  bxh_file="${main_base}.bxh"
  if [[ ! -f "$bxh_file" ]]; then
    # fallback: first non-revphase BXH in the same directory
    bxh_file="$(ls -1 "$(dirname "$main_nii")"/*.bxh 2>/dev/null | grep -vi 'revphase' | head -n1)"
# (auto-removed stray)   fi

  if [[ -n "$bxh_file" && -f "$bxh_file" ]]; then
    echo "[auto] BXH found: $bxh_file"
    # Prefer helper if present (local→ssh andros→scp), else run local extractdiffdirs
    if declare -f run_extractdiffdirs >/dev/null 2>&1; then
      run_extractdiffdirs "$bxh_file" "$main_base" || echo "[warn] run_extractdiffdirs failed"
    else
      if command -v extractdiffdirs >/dev/null 2>&1; then
        extractdiffdirs "$bxh_file" "$main_base" || echo "[warn] extractdiffdirs failed"
      else
        echo "[warn] extractdiffdirs not available and no helper; cannot extract from BXH."
# (auto-removed stray)       fi
# (auto-removed stray)     fi

    # refresh sources after attempted extraction
    src_bvec="${main_base}.bvec"
    src_bval="${main_base}.bval"
    [[ -s "$src_bvec" && -s "$src_bval" ]] && have_grads=1
  else
    echo "[note] No BXH sibling found for ${main_nii}; skipping BXH extraction."
# (auto-removed stray)   fi
# (auto-removed stray) fi

# now, only copy if we actually have grads
if [[ $have_grads -eq 1 ]]; then
  echo "[grads] using $src_bvec / $src_bval"
  # your script defines Bvecs/Bvals paths already; guard the copies
  if [[ -n "${Bvecs:-}" ]]; then cp -f "$src_bvec" "$Bvecs"; fi
  if [[ -n "${Bvals:-}" ]]; then cp -f "$src_bval" "$Bvals"; fi
else
  echo "[warn] No gradients available as .bvec/.bval; downstream must infer from .mif or JSON."
# (auto-removed stray) fi
# --- END robust gradients resolution ---

if [[ ! -f ${bvecs} ]];then
# (auto-disabled) 	cp ${raw_nii/\.nii\.gz/\.bvec} ${bvecs}
# (auto-removed stray) fi

if [[ ! -f ${bvals} ]];then
	cp ${raw_nii/\.nii\.gz/\.bval} ${bvals}
# (auto-removed stray) fi



if [[ ! -f ${bvecs} ]];then
    bvec_cmd="extractdiffdirs --colvectors --writebvals --fieldsep=\t --space=RAI ${bxheader} ${bvecs} ${bvals}";
    $bvec_cmd;
# (auto-removed stray) fi

mrtrix_grad_table="${bvals%.b*}_grad_corrected.b";

#######
presumed_debiased_stage='05';
# Add one to presumed_debiased_stage:
pds_plus_one='06';
debiased=${work_dir}/${id}_${presumed_debiased_stage}_dwi_nii4D_biascorrected.mif
if [[ ! -f ${debiased} ]];then

	###
	# Adding stage 00, checking the gradient table.
	stage='00';	
	if [[ ! -e ${mrtrix_grad_table} ]];then	
		dwigradcheck ${raw_nii} -fslgrad ${bvecs} ${bvals} -export_grad_mrtrix ${mrtrix_grad_table};
# (auto-removed stray) 	fi
	
	if [[ ! -f ${mrtrix_grad_table} ]];then
		echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) 	fi
	
	###
	# 3. --> 1. Convert DWI data to MRtrix format
	stage='01';
	dwi_mif=${work_dir}/${id}_${stage}_dwi_nii4D.mif;
	if [[ ! -f ${dwi_mif} ]];then
		# Moved convert to mif from stage 3 to stage 1
		#mrconvert ${degibbs} ${dwi_mif} -fslgrad ${bvecs} ${bvals};
		mrconvert ${raw_nii} ${dwi_mif} -grad ${mrtrix_grad_table};
# (auto-removed stray) 	fi
	
	if [[ ! -f ${dwi_mif} ]];then
		echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) 	fi
	
	
	###
	# 1. --> 2. Denoise the raw DWI data
	stage='02';
	#denoised=${work_dir}/${id}_${stage}_dwi_nii4D_denoised.nii.gz
	denoised=${work_dir}/${id}_${stage}_dwi_nii4D_denoised.mif
	if [[ ! -f ${denoised} ]];then
		# Moved denoise from stage 1 to stage 2:
		#dwidenoise $raw_nii ${denoised}
		dwidenoise ${dwi_mif} ${denoised}
# (auto-removed stray) 	fi
	
	if [[ ! -f ${denoised} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${dwi_mif} ]];then
			rm ${dwi_mif};
# (auto-removed stray) 		fi
# (auto-removed stray) 	fi
	
	###
	# 2. --> 3 Gibbs ringing correction (optional)
	stage='03';
	#degibbs=${work_dir}/${id}_${stage}_dwi_nii4D_degibbs.nii.gz;
	degibbs=${work_dir}/${id}_${stage}_dwi_nii4D_degibbs.mif;
	if [[ ! -f ${degibbs} ]];then
		mrdegibbs ${denoised} ${degibbs}
# (auto-removed stray) 	fi
	
	if [[ ! -f ${degibbs} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${denoised} ]];then
			rm ${denoised};
# (auto-removed stray) 		fi
# (auto-removed stray) 	fi
	###
	# 4. Perform motion and eddy current correction (requires FSL's `eddy`)
	# OR alternatively, see how well our coreg performs.
# === AUTO: detect PhaseEncodingDirection and TotalReadoutTime from JSON ===
auto_main="$( 
  j=$(json_for "$raw_nii"); 
  if [[ -n "$j" ]]; then 
    bp=$(jq -r '."PhaseEncodingDirection" // empty' "$j" 2>/dev/null); 
    ro=$(readout_from_json "$j"); 
    mp=$(pe_bids_to_mrtrix "$bp"); 
    echo "${mp}|${ro}"; 
# (auto-removed stray)   fi
)"
auto_pe="${auto_main%%|*}"; auto_ro="${auto_main##*|}"
[[ -z "${pe_dir_main:-}" || "${pe_dir_main}" == "auto" ]] && pe_dir_main="$auto_pe"
[[ -z "${pe_dir_main}" ]] && pe_dir_main="AP"
[[ -z "${readout_time:-}" ]] && readout_time="$auto_ro"
if [[ -n "${revpe:-}" && -f "$revpe" ]]; then
  rev_pe="$( j=$(json_for "$revpe"); [[ -n "$j" ]] && jq -r '."PhaseEncodingDirection" // empty' "$j" 2>/dev/null | xargs -I{{}} bash -lc 'pe_bids_to_mrtrix \"{{}}\"' )"
  exp="$(opposite_of "$pe_dir_main")"
  [[ -n "$rev_pe" && -n "$exp" && "$rev_pe" != "$exp" ]] && echo "[note] reverse PE $rev_pe != expected $exp"
# (auto-removed stray) fi
stage='04';

preprocessed=${work_dir}/${id}_${stage}_dwi_nii4D_preprocessed.mif;
temp_mask=${work_dir}/${id}_mask_tmp.mif;

if [[ ! -f ${preprocessed} ]];then
  if ((${use_fsl}));then
    if [[ ! -f ${temp_mask} ]];then dwi2mask ${degibbs} ${temp_mask}; fi
    mask_string=' '
    if [[ -f ${temp_mask} ]]; then mask_string=" -mask ${temp_mask} "; fi

    eddy_opts='--repol --slm=linear'
    n_shells=$(mrinfo -shell_bvalues ${degibbs} | wc -w)
    if [[ ${n_shells} -gt 2 ]]; then eddy_opts="${eddy_opts} --data_is_shelled "; fi

    se_epi=""; se_epi_nii="${work_dir}/${id}_rev_seepi.nii.gz"
    if [[ -n "${revpe:-}" && -f "${revpe}" ]]; then
      rev_base="${revpe%.gz}"; rev_base="${rev_base%.nii}"
      if [[ -f "${rev_base}.bval" ]]; then
        idx=$(awk '{for(i=1;i<=NF;i++) if ($i<50){print (i-1); exit}}' "${rev_base}.bval" || true)
        [[ -z "$idx" ]] && idx=0
        fslroi "${revpe}" "${se_epi_nii}" "$idx" 1
      else
        cp "${revpe}" "${se_epi_nii}"
# (auto-removed stray)       fi
      se_epi="${se_epi_nii}"
# (auto-removed stray)     fi

    # Fallback: if reverse is single-volume and we didn\'t build se_epi, use reverse directly
    if [[ -z "$se_epi" && -n "${revpe:-}" && -f "$revpe" ]]; then
      nvol=$(fslval "$revpe" dim4 2>/dev/null || echo 1)
      if [[ -z "$nvol" || "$nvol" -eq 1 ]]; then
        se_epi="$revpe"
        echo "[stage 04] Fallback: using reverse as SE-EPI -> $se_epi"
# (auto-removed stray)       fi
# (auto-removed stray)     fi

    if [[ -n "$se_epi" && -n "${readout_time:-}" ]]; then
      echo "[stage 04] Using TOPUP+EDDY with -rpe_pair (pe_dir=${pe_dir_main}, readout=${readout_time}s)."
      dwifslpreproc ${degibbs} ${preprocessed} \
        -pe_dir ${pe_dir_main} \
        -rpe_pair -se_epi "${se_epi}" \
        -readout_time ${readout_time} \
        -eddy_options " ${eddy_opts} " \
        -scratch ${work_dir}/ -nthreads 10 ${mask_string}
    else
      echo "[stage 04] No reverse-PE inputs; using -rpe_none (pe_dir=${pe_dir_main})."
      dwifslpreproc ${degibbs} ${preprocessed} \
        -pe_dir ${pe_dir_main} -rpe_none \
        -eddy_options " ${eddy_opts} " \
        -scratch ${work_dir}/ -nthreads 10 ${mask_string}
# (auto-removed stray)     fi
  else
    : # (non-FSL branch left as-is in your script outside this replace)
# (auto-removed stray)   fi
# (auto-removed stray) fi
stage='05';
	debiased=${work_dir}/${id}_${stage}_dwi_nii4D_biascorrected.mif
	mask_string=' ';
	if [[ -f ${tmp_mask} ]];then
		mask_string=" -mask ${temp_mask} ";
# (auto-removed stray) 	fi
	if [[ ! -f ${debiased} ]];then
		dwibiascorrect ants ${preprocessed} ${debiased} -scratch ${work_dir}/
# (auto-removed stray) 	fi
	
	if [[ ! -f ${debiased} ]];then
		echo "Process died during stage ${stage}" && exit 1;
	elif ((${cleanup}));then
		if [[ -f ${preprocessed} ]];then
			rm ${preprocessed};
# (auto-removed stray) 		fi
		
		if [[ -f ${temp_mask} ]];then
			rm ${temp_mask};
# (auto-removed stray) 		fi
# (auto-removed stray) 	fi
else
	echo "Debiased mif file already exists; skipping to Stage ${pds_plus_one}." 
# (auto-removed stray) fi


###
# 6. Extract b0 and dwi from debiased nii4D
stage='06';

b0=${work_dir}/${id}_b0.nii.gz;
dwi=${work_dir}/${id}_dwi.nii.gz;

shells=$(mrinfo -shell_bvalues ${debiased});
# We remove the first shell, assuming it is the B0 value.
# shells=${shells#*\ };
# Trim trailing space.
shells=${shells%\ };

shellmeans=${work_dir}/${id}_shellmeans.mif;	
if [[ ! -f ${b0} || ! -f ${dwi} ]];then
	if [[ ! -f ${shellmeans} ]]; then
		dwishellmath ${debiased} mean ${shellmeans};
# (auto-removed stray) 	fi
	
	i=0;
	for shelly_long in ${shells};do
		if (($i));then
			c_image="${work_dir}/${id}_dwi_b${shelly_long}.nii.gz";
		else
			c_image="${work_dir}/${id}_b0.nii.gz";
# (auto-removed stray) 		fi	
		
		if [[ ! -e ${c_image} ]];then
			mrconvert ${shellmeans} -coord 3 ${i} -axes 0,1,2 ${c_image};
# (auto-removed stray) 		fi
		let "i++";
	done
	
	dwi_stack_mif="${work_dir}/${id}_dwi_stack.mif";
	
	if [[ ! -f ${dwi} ]];then 
		if [[ $i -eq 2 ]];then
			mv ${c_image} ${dwi};
		else
			if [[ ! -f ${dwi_stack_mif} ]];then
				s_idc=$(mrinfo -shell_indices ${debiased});
				s_idc=${s_idc#*\ };
				s_idc=${s_idc%\ };
				s_idc=${s_idc// /,};
			
				mrconvert ${debiased} ${dwi_stack_mif} -coord 3 ${s_idc};
# (auto-removed stray) 			fi
			mrmath ${dwi_stack_mif} mean ${dwi} -axis 3;
			
			if [[ ! -f ${dwi} ]];then
				echo "Process died during stage ${stage}" && exit 1;
			elif ((${cleanup}));then
				if [[ -f ${dwi_stack_mif} ]];then
					rm ${dwi_stack_mif};
# (auto-removed stray) 				fi
# (auto-removed stray) 			fi
			
			if [[ ! -f ${b0} ]];then
				echo "Process died during stage ${stage}" && exit 1;
			elif ((${cleanup}));then
				if [[ -f ${shellmeans} ]];then
					rm ${shellmeans};
# (auto-removed stray) 				fi
# (auto-removed stray) 			fi
# (auto-removed stray) 		fi
# (auto-removed stray) 	fi
# (auto-removed stray) fi

if [[ ! -f ${b0} || ! -f ${dwi} ]];then
	echo "Process died during stage ${stage}" && exit 1;
elif ((${cleanup}));then
	if [[ -f ${shellmeans} ]];then
		rm ${shellmeans};
# (auto-removed stray) 	fi
	if [[ -f ${dwi_stack_mif} ]];then
		rm ${dwi_stack_mif};
# (auto-removed stray) 	fi
# (auto-removed stray) fi


# With b0 in hand, generate a mask with fsl's bet:
mask=${work_dir}/${id}_mask.nii.gz;
if [[ ! -f ${mask} ]];then
	if [[ -f ${b0} ]];then
		bet ${b0} ${mask%_mask.nii.gz} -m -n;
		fslmaths ${mask} -add 0 ${mask} -odt "char";
# (auto-removed stray) 	fi
# (auto-removed stray) fi

if [[ ! -f ${mask} ]];then
	echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) fi



###
# 7. Fit the tensor model
stage='07';

strides=${work_dir}/${id}_strides.txt
if [[ ! -f $strides ]];then
	mrinfo -strides ${debiased} > $strides;
# (auto-removed stray) fi
dt=${work_dir}/${id}_${stage}_dt.mif;
if [[ ! -f ${dt} || ! -f ${b0} ]];then
	dwi2tensor ${debiased} ${dt} -mask ${mask};
# (auto-removed stray) fi

if [[ ! -f ${dt} ]];then
	echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) fi
###
# 8. Compute FA (and other metrics, if desired)
stage='08';
fa=${work_dir}/${id}_${stage}_fa.mif;
fa_nii=${work_dir}/${id}_fa.nii.gz;
adc=${work_dir}/${id}_${stage}_adc.mif;
adc_nii=${work_dir}/${id}_adc.nii.gz;
rd=${work_dir}/${id}_${stage}_rd.mif;
rd_nii=${work_dir}/${id}_rd.nii.gz;
ad=${work_dir}/${id}_${stage}_ad.mif;
ad_nii=${work_dir}/${id}_ad.nii.gz;
out_string=" ";

if [[ ! -f ${fa_nii} || ! -f ${adc_nii} || ! -f ${rd_nii} || ! -f ${ad_nii} ]];then

	if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]];then
		for contrast in fa adc rd ad;do
			c_mif=${work_dir}/${id}_${stage}_${contrast}.mif;
			nii=${work_dir}/${id}_${contrast}.nii.gz;
			if [[ ! -f ${nii} && ! -f ${c_mif} ]];then
				out_string="${out_string} -${contrast} ${c_mif}"
# (auto-removed stray) 			fi
		done
		tensor2metric ${dt} ${out_string};
# (auto-removed stray) 	fi

	if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]];then
		echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) 	fi
# (auto-removed stray) fi

###
# 9. Convert FA (or other metrics) to NIfTI for visualization
for contrast in fa adc rd ad;do
	mif=${work_dir}/${id}_${stage}_${contrast}.mif;
	nii=${work_dir}/${id}_${contrast}.nii.gz;
	
	if [[ ! -f ${nii} ]];then
		mrconvert ${mif} ${nii};
# (auto-removed stray) 	fi
	
	if [[ -f ${nii} && -f ${mif} ]];then
		if ((${cleanup}));then
			rm ${mif};
# (auto-removed stray) 		fi
# (auto-removed stray) 	fi
done


###
# 10. Estimating the response functions
stage='10';
wm_txt=${work_dir}/${id}_wm.txt;
gm_txt=${work_dir}/${id}_gm.txt;
csf_txt=${work_dir}/${id}_csf.txt;
voxels_mif=${work_dir}/${id}_voxels.mif.gz

if [[ ! -f ${wm_txt} || ! -f ${gm_txt} || ! -f ${csf_txt} || ! -f ${voxels_mif} ]];then
	dwi2response dhollander ${debiased} ${wm_txt} ${gm_txt} ${csf_txt} -voxels ${voxels_mif} -mask ${mask} -scratch ${work_dir};
# (auto-removed stray) fi

if [[ ! -f ${wm_txt} || ! -f ${gm_txt} || ! -f ${csf_txt} || ! -f ${voxels_mif} ]];then
	echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) fi

###
# 11. Applying the basis functions to the diffusion data:
stage='11';
wmfod_mif=${work_dir}/${id}_wmfod.mif.gz;
gmfod_mif=${work_dir}/${id}_gmfod.mif.gz;
csffod_mif=${work_dir}/${id}_csffod.mif.gz;

if [[ ! -f ${wmfod_mif} ]];then
	dwi2fod msmt_csd ${debiased} -mask ${mask} ${wm_txt} ${wmfod_mif};
# (auto-removed stray) fi

if [[ ! -f ${wmfod_mif} ]];then
	echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) fi

###
# 12. Normalize the FODs:
stage='12';
wmfod_norm_mif=${work_dir}/${id}_wmfod_norm.mif.gz
#gmfod_norm_mif=${work_dir}/${id}_gmfod_norm.mif.gz
#csffod_norm_mif=${work_dir}/${id}_csffod_norm.mif,gz  
if [[ ! -f ${wmfod_norm_mif} ]];then
	mtnormalise ${wmfod_mif} ${wmfod_norm_mif} -mask ${mask};
# (auto-removed stray) fi

if [[ ! -f ${wmfod_norm_mif} ]];then
	echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) fi

###
# 13. Creating streamlines with tckgen
stage='13';
tracks_10M_tck=${work_dir}/${id}_tracks_10M.tck;
smaller_tracks=${work_dir}/${id}_smaller_tracks_2M.tck;
if [[ ! -f ${smaller_tracks} ]];then
	if [[ ! -f ${tracks_10M_tck} ]];then
		tckgen -backtrack -seed_image ${mask} -maxlength 1000 -cutoff 0.1 -select 10000000 ${wmfod_norm_mif} ${tracks_10M_tck} -nthreads 10;
# (auto-removed stray) 	fi
	
	if [[ ! -f ${tracks_10M_tck} ]];then
		echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) 	fi
	###
	# 14. Extracting a subset of tracks.
	stage='14';
	tckedit ${tracks_10M_tck} -number 2000000 -minlength 0.1 ${smaller_tracks};
# (auto-removed stray) fi

if [[ ! -f ${smaller_tracks} ]];then
	echo "Process died during stage ${stage}" && exit 1;
elif ((${cleanup}));then
	if [[ -f ${tracks_10M_tck}  ]];then
		rm ${tracks_10M_tck};
# (auto-removed stray) 	fi
# (auto-removed stray) fi
###
# 14.5 Further reducing tracks solely for QA visualization purpose.
stage=14.5;
QA_tracks=${work_dir}/${id}_QA_tracks_50k.tck;
if [[ ! -f ${QA_tracks} ]];then
	tckedit ${smaller_tracks} ${QA_tracks} -number 50000 -nthreads 10;
# (auto-removed stray) fi

if [[ ! -f ${QA_tracks} ]];then
	echo "NON-CRITICAL FAILURE: no QA_tracks were produced during stage ${stage}." ;
	echo "   Missing file: ${QA_tracks} ." ;
# (auto-removed stray) fi

###
# 15. Sifting the tracks with tcksift2: bc some wm tracks are over or underfitted
stage='15';
sift_mu_txt=${work_dir}/${id}_sift_mu.txt;
sift_coeffs_txt=${work_dir}/${id}_sift_coeffs.txt;
sift_1M_txt=${work_dir}/${id}_sift_1M.txt;

if [[ ! -f  ${sift_mu_txt} || ! -f ${sift_coeffs_txt} || ! -f ${sift_1M_txt} ]];then
	tcksift2  -out_mu ${sift_mu_txt} -out_coeffs ${sift_coeffs_txt} ${smaller_tracks} ${wmfod_norm_mif} ${sift_1M_txt} ;
# (auto-removed stray) fi

if [[ ! -f  ${sift_mu_txt} || ! -f ${sift_coeffs_txt} || ! -f ${sift_1M_txt} ]];then
	echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) fi

###
# 16. Convert and remap IIT labels
stage='16';

labels=${work_dir}/${id}_IITmean_RPI_labels.nii.gz;

if [[ ! -e ${labels} ]];then
	source_labels=${BIGGUS_DISKUS}/../mouse/VBM_25${project}01_IITmean_RPI-results/connectomics/${id}/${id}_IITmean_RPI_labels.nii.gz;
	if [[ -e ${source_labels} ]];then
		cp ${source_labels} ${labels};
# (auto-removed stray) 	fi
	if [[ ! -e ${labels} ]];then
		echo "Process stopped at ${stage}.";
		echo "SAMBA labels do not exist yet."
		echo "Please run samba-pipe and backport the labels to this folder." && exit 0;
# (auto-removed stray) 	fi
# (auto-removed stray) fi

parcels_mif=${work_dir}/${id}_IITmean_RPI_parcels.mif.gz;

if [[ ! -f ${parcels_mif} ]];then
	mrconvert ${labels} ${parcels_mif};
# (auto-removed stray) fi
	
max_label=$(mrstats -output max ${parcels_mif} | cut -d ' ' -f1);

if [[ max_label -gt 84 ]];then
	index2=(8 10 11 12 13 17 18 26 47 49 50 51 52 53 54 58 1001 1002 1003 1005 1006 1007 1008 1009 1010 1011 1012 1013 1014	1015 1016 1017 1018 1019 1020 1021 1022 1023 1024 1025 1026 1027 1028 1029 1030 1031 1032 1033 1034 1035 2001 2002 2003 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024 2025 2026 2027 2028 2029 2030 2031 2032 2033 2034 2035);
	decomp_parcels=${parcels_mif%\.gz};
	if [[ ! -f ${decomp_parcels} ]];then
		gunzip ${parcels_mif};
# (auto-removed stray) 	fi 

	for i in $(seq 1 84);do
		mrcalc ${decomp_parcels} ${index2[$i-1]} $i -replace ${decomp_parcels} -force;
	done
	
	if [[ -f ${parcels_mif} ]];then
		rm ${parcels_mif}
# (auto-removed stray) 	fi
	gzip ${decomp_parcels};
# (auto-removed stray) fi

max_label=$(mrstats -output max ${parcels_mif} | cut -d ' ' -f1);
if [[ ${max_label} -gt 84 ]];then
	echo "Process died during stage ${stage}" && exit 1;
# (auto-removed stray) fi



###
# 17. Calculate connectomes
stage='17';
conn_folder=/mnt/newStor/paros//paros_WORK/${project}_connectomics/${id}_connectomics;
if ((! $use_fsl));then
	conn_folder=/mnt/newStor/paros//paros_WORK/${project}_connectomics/${id}_with_coreg_connectomics;
# (auto-removed stray) fi
if [[ ! -d ${conn_folder} ]];then
	mkdir ${conn_folder};
# (auto-removed stray) fi

distances_csv=${conn_folder}/${id}_distances.csv;
if [[ ! -f ${distances_csv} ]];then
	echo "File not found: ${distances_csv}; Running tck2connectome...";
	tck2connectome ${smaller_tracks} ${parcels_mif} ${distances_csv} -zero_diagonal -symmetric -scale_length -stat_edge  mean;
# (auto-removed stray) fi


mean_FA_per_streamline=${conn_folder}/${id}_per_strmline_mean_FA.csv;


if [[ ! -f ${mean_FA_per_streamline} ]];then
	tcksample ${smaller_tracks} ${fa_nii} ${mean_FA_per_streamline} -stat_tck mean;
# (auto-removed stray) fi

mean_FA_connectome=${conn_folder}/${id}_mean_FA_connectome.csv;
if [[ ! -f ${mean_FA_connectome} ]];then
	echo "File not found: ${mean_FA_connectome}; Running tck2connectome...";‘
	tck2connectome ${smaller_tracks} ${parcels_mif} ${mean_FA_connectome} -zero_diagonal -symmetric -scale_file ${mean_FA_per_streamline} -stat_edge mean;
# (auto-removed stray) fi



###
# 18.
stage='18';

# I think we decided we didn't want/need this first flavor
#parcels_csv=${conn_folder}/${id}_conn_sift_node.csv;
#assignments_parcels_csv=${conn_folder}/${id}_assignments_con_sift_node.csv;
#os.system('tck2connectome -symmetric -zero_diagonal -scale_invnodevol -tck_weights_in '+ sift_1M_txt+ ' '+ smallerTracks + ' '+ parcels_mif + ' '+ parcels_csv + ' -out_assignment ' + assignments_parcels_csv + ' -force')


parcels_csv_2=${conn_folder}/${id}_con_plain.csv;
assignments_parcels_csv2=${conn_folder}/${id}_assignments_con_plain.csv;
if [[ ! -f ${parcels_csv_2} ||  ! -f ${assignments_parcels_csv2} ]];then
	echo "File not found: ${parcels_csv_2}; Running tck2connectome...";
	tck2connectome -symmetric -zero_diagonal ${smaller_tracks} ${parcels_mif} ${parcels_csv_2} -out_assignment ${assignments_parcels_csv2} -force;
# (auto-removed stray) fi

parcels_csv_3=${conn_folder}/${id}_con_sift.csv;
assignments_parcels_csv3=${conn_folder}/${id}_assignments_con_sift.csv;
if [[ ! -f ${parcels_csv_3} ||  ! -f ${assignments_parcels_csv3} ]];then
	echo "File not found: ${parcels_csv_3}; Running tck2connectome...";
	tck2connectome -symmetric -zero_diagonal -tck_weights_in ${sift_1M_txt} ${smaller_tracks} ${parcels_mif} ${parcels_csv_3} -out_assignment ${assignments_parcels_csv3} -force;
# (auto-removed stray) fi

echo "The ${proc_name}_${id} pipeline has completed! Thanks for patronizing this wonderful script!" && exit 0
#######
