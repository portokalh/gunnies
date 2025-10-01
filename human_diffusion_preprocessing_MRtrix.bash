#! /bin/bash

## 15 June 2020, BJA: I still need to figure out the best way to pull out the non-zero bval(s) from the bval file.
## For now, hardcoding it to 1000 to run Whitson data. # 8 September 2020, BJA: changing to 800 for Sinha data.
## 24 January 2022, BJA: Changing bval to 2400 for Manisha's data.
## 21 January 2025, BJA: Totally rewrote based around chatGPT's answer when asking how to preprocess using MRtrix

project=ADRC

# ====== HELPERS ======
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

# Prefer venv-backed wrapper in /usr/local/bin if present
_resolve_extract_bin() {
  if [[ -x /usr/local/bin/extractdiffdirs ]]; then
    echo /usr/local/bin/extractdiffdirs
  elif command -v extractdiffdirs >/dev/null 2>&1; then
    command -v extractdiffdirs
  else
    echo ""
  fi
}
 
# Use BXH to produce BOTH .bvec and .bval (no synthesis). Fail if missing.
run_extractdiffdirs() {
  local bxh_file="$1"     # e.g. /path/subj/run.bxh
  local out_bvec="$2"     # e.g. /path/subj/run.bvec   (FULL path, not prefix)
  local out_bval="$3"     # e.g. /path/subj/run.bval

  # Prefer your venv-backed wrapper
  export PATH=/usr/local/bin:$PATH

  [[ -f "$bxh_file" ]] || { echo "[ERR] BXH not found: $bxh_file"; return 2; }
  [[ -n "$out_bvec" && -n "$out_bval" ]] || { echo "[ERR] need explicit out_bvec & out_bval"; return 2; }
  mkdir -p "$(dirname "$out_bvec")"
  rm -f "$out_bvec" "$out_bval"  # avoid "exists" aborts

  echo "[BXH] extractdiffdirs --colvectors --writebvals --fieldsep=\\t --space=RAI '$bxh_file' '$out_bvec' '$out_bval'"
  if ! extractdiffdirs \
        --colvectors \
        --writebvals \
        --fieldsep='\t' \
        --space=RAI \
        "$bxh_file" "$out_bvec" "$out_bval"; then
    echo "[ERR] extractdiffdirs failed"
    return 3
  fi

  # Verify outputs exist & look like FSL-format bvec (3 x N) and bval (1 x N)
  [[ -s "$out_bvec" && -s "$out_bval" ]] || { echo "[ERR] BXH did not write both outputs"; return 4; }

  local r c bc
  r=$(awk 'END{print NR}' "$out_bvec")
  c=$(awk 'NR==1{print NF; exit}' "$out_bvec")
  bc=$(awk 'NR==1{print NF; exit}' "$out_bval")

  if [[ "$r" -ne 3 ]]; then
    echo "[ERR] bvec is ${r}x${c}; expected 3xN (colvectors yields 3 rows)."
    return 5
  fi

  # optional: check volume count matches file’s dim4 (warn only)
  if command -v fslval >/dev/null 2>&1; then
    local nvol; nvol=$(fslval "${raw_nii:-$bxh_file}" dim4 2>/dev/null || echo "")
    [[ -n "$nvol" && "$c" -ne "$nvol" ]] && echo "[warn] bvec cols ($c) != volumes ($nvol)"
    [[ -n "$nvol" && "$bc" -ne "$nvol" ]] && echo "[warn] bval cols ($bc) != volumes ($nvol)"
  fi

  echo "[BXH] OK -> $out_bvec / $out_bval (3x$c, 1x$bc)"
  return 0
}
  

# Process name
proc_name="diffusion_prep_MRtrix"

# Locate GUNNIES root
if [[ -d ${GUNNIES} ]]; then
  GD=${GUNNIES}
else
  GD=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
fi

## Determine if we are running on a cluster
cluster=$(bash cluster_test.bash);
if [[ $cluster ]]; then
  if [[ ${cluster} -eq 1 ]]; then
    sub_script=${GD}/submit_slurm_cluster_job.bash
  fi
  if [[ ${cluster} -eq 2 ]]; then
    sub_script=${GD}/submit_sge_cluster_job.bash
  fi
  echo "Great News, Everybody! It looks like we're running on a cluster, which should speed things up tremendously!";
fi

BD=${BIGGUS_DISKUS}
if [[ ! -d ${BD} ]]; then
  echo "env variable 'BIGGUS_DISKUS' not defined...failing now..."  && exit 1
fi

# Ensure we route to 'human' dir
BD2=${BD%/}
mama_dir=${BD2%/*}
baby_dir=${BD2##*/}
if [[ "xmousex" == "x${baby_dir}x" ]]; then
  BD="${mama_dir}/human/"
  export BIGGUS_DISKUS=$BD
  if [[ ! -d $BD ]]; then
    mkdir -m 775 ${BD}
  fi
fi

id=$1
raw_nii=$2
no_cleanup=$3

# === folder input normalization (largest=main, second-largest=reverse) ===
if [[ -d "$raw_nii" ]]; then
  echo "[auto] Directory input: $raw_nii"
  mapfile -t _nii < <(find "$raw_nii" -maxdepth 1 -type f \( -iname "*.nii" -o -iname "*.nii.gz" \) \
                      -printf "%s\t%p\n" | sort -nr | awk 'NR<=2{print $2}')
  if [[ ${#_nii[@]} -lt 1 ]]; then
    echo "[ERR] No NIfTI files in $raw_nii"; exit 2
  fi
  raw_nii="${_nii[0]}"
  revpe="${_nii[1]:-}"
  echo "[auto] main DWI: $raw_nii"
  [[ -n "$revpe" ]] && echo "[auto] reverse: $revpe"
fi

# cleanup flag
if [[ "x1x" == "x${no_cleanup}x" ]]; then
  cleanup=0
else
  cleanup=1
fi

echo "Processing diffusion data with runno/id: ${id}."

# Always use FSL branch
use_fsl=1	
work_dir=${BD}/${proc_name}_${id}

echo "Work directory: ${work_dir}"
[[ -d ${work_dir} ]] || mkdir -pm 775 ${work_dir}

sbatch_folder=${work_dir}/sbatch
[[ -d ${sbatch_folder} ]] || mkdir -pm 775 ${sbatch_folder}

nii_name=${raw_nii##*/}
ext="nii.gz"

bxheader=${raw_nii/nii.gz/bxh}

bvecs=${work_dir}/${id}_bvecs.txt
bvals=${work_dir}/${id}_bvals.txt
echo "Bvecs: ${bvecs}"

# --- Robust gradients resolution (NIfTI sidecars or BXH via extractdiffdirs) ---
main_nii="${raw_nii}"
main_base="${main_nii%.gz}"; main_base="${main_base%.nii}"
src_bvec="${main_base}.bvec"
src_bval="${main_base}.bval"
have_grads=0
if [[ -s "$src_bvec" && -s "$src_bval" ]]; then
  have_grads=1
else
  echo "[auto] No .bvec/.bval next to ${main_nii}; trying to extract from BXH…"
  bxh_file="${main_base}.bxh"
  if [[ ! -f "$bxh_file" ]]; then
    bxh_file="$(ls -1 "$(dirname "$main_nii")"/*.bxh 2>/dev/null | grep -vi 'revphase' | head -n1 || true)"
  fi
  if [[ -n "$bxh_file" && -f "$bxh_file" ]]; then
    echo "[auto] BXH found: $bxh_file"
	if declare -f run_extractdiffdirs >/dev/null 2>&1; then
	  # Use explicit outputs + your proven flags; fail hard if both files aren’t written
	  run_extractdiffdirs "$bxh_file" "$src_bvec" "$src_bval" \
		|| { echo "[ERR] BXH extraction failed"; exit 1; }
	else
	  EXTRACT_BIN=$(_resolve_extract_bin)
	  if [[ -n "$EXTRACT_BIN" ]]; then
		"$EXTRACT_BIN" --colvectors --writebvals --fieldsep='\t' --space=RAI \
		  "$bxh_file" "$src_bvec" "$src_bval" \
		  || { echo "[ERR] extractdiffdirs failed"; exit 1; }
	  else
		echo "[ERR] extractdiffdirs not available and no helper; cannot extract from BXH."
		exit 1
	  fi
	fi
	[[ -s "$src_bvec" && -s "$src_bval" ]] && have_grads=1

  else
    echo "[note] No BXH sibling found for ${main_nii}; skipping BXH extraction."
  fi
fi
if [[ $have_grads -eq 1 ]]; then
  echo "[grads] using $src_bvec / $src_bval"
  cp -f "$src_bvec" "$bvecs"
  cp -f "$src_bval" "$bvals"
else
  echo "[warn] No gradients available as .bvec/.bval; downstream must infer from .mif or JSON."
fi
# ------------------------------------------------------------------------------

mrtrix_grad_table="${work_dir}/${id}_grad_corrected.b"

#######
presumed_debiased_stage='05'
pds_plus_one='06'
debiased=${work_dir}/${id}_${presumed_debiased_stage}_dwi_nii4D_biascorrected.mif
if [[ ! -f ${debiased} ]]; then

  # 00. Check / fix gradients and export MRtrix format
  stage='00'
  if [[ ! -e ${mrtrix_grad_table} ]]; then
    dwigradcheck ${raw_nii} -fslgrad ${bvecs} ${bvals} -export_grad_mrtrix ${mrtrix_grad_table}
  fi
  if [[ ! -f ${mrtrix_grad_table} ]]; then
    echo "Process died during stage ${stage}" && exit 1
  fi

  # 01. Convert DWI to .mif with corrected gradients
  stage='01'
  dwi_mif=${work_dir}/${id}_${stage}_dwi_nii4D.mif
  if [[ ! -f ${dwi_mif} ]]; then
    mrconvert ${raw_nii} ${dwi_mif} -grad ${mrtrix_grad_table}
  fi
  if [[ ! -f ${dwi_mif} ]]; then
    echo "Process died during stage ${stage}" && exit 1
  fi

  # 02. Denoise
  stage='02'
  denoised=${work_dir}/${id}_${stage}_dwi_nii4D_denoised.mif
  if [[ ! -f ${denoised} ]]; then
    dwidenoise ${dwi_mif} ${denoised}
  fi
  if [[ ! -f ${denoised} ]]; then
    echo "Process died during stage ${stage}" && exit 1
  elif ((${cleanup})); then
    [[ -f ${dwi_mif} ]] && rm ${dwi_mif}
  fi

  # 03. Gibbs ringing correction
  stage='03'
  degibbs=${work_dir}/${id}_${stage}_dwi_nii4D_degibbs.mif
  if [[ ! -f ${degibbs} ]]; then
    mrdegibbs ${denoised} ${degibbs}
  fi
  if [[ ! -f ${degibbs} ]]; then
    echo "Process died during stage ${stage}" && exit 1
  elif ((${cleanup})); then
    [[ -f ${denoised} ]] && rm ${denoised}
  fi

  # === Auto-detect PE dir and readout time from JSON ===
  auto_main_pe=""; auto_main_ro=""
  j_main=$(json_for "$raw_nii" || true)
  if [[ -n "$j_main" ]]; then
    bids_pe=$(jq -r '."PhaseEncodingDirection" // empty' "$j_main" 2>/dev/null)
    auto_main_pe=$(pe_bids_to_mrtrix "$bids_pe")
    auto_main_ro=$(readout_from_json "$j_main")
  fi
  pe_dir_main="${pe_dir_main:-$auto_main_pe}"
  [[ -z "$pe_dir_main" ]] && pe_dir_main="AP"
  readout_time="${readout_time:-$auto_main_ro}"

  if [[ -n "${revpe:-}" && -f "$revpe" ]]; then
    j_rev=$(json_for "$revpe" || true)
    if [[ -n "$j_rev" ]]; then
      rev_bids_pe=$(jq -r '."PhaseEncodingDirection" // empty' "$j_rev" 2>/dev/null)
      rev_pe_dir=$(pe_bids_to_mrtrix "$rev_bids_pe")
      exp=$(opposite_of "$pe_dir_main")
      [[ -n "$rev_pe_dir" && -n "$exp" && "$rev_pe_dir" != "$exp" ]] && echo "[note] reverse PE $rev_pe_dir != expected $exp"
    fi
  fi

  # 04. TOPUP + EDDY (dwifslpreproc)
  stage='04'
  preprocessed=${work_dir}/${id}_${stage}_dwi_nii4D_preprocessed.mif
  temp_mask=${work_dir}/${id}_mask_tmp.mif

  if [[ ! -f ${preprocessed} ]]; then
    if ((${use_fsl})); then
      # quick mask
      if [[ ! -f ${temp_mask} ]]; then dwi2mask ${degibbs} ${temp_mask}; fi
      mask_string=' '
      [[ -f ${temp_mask} ]] && mask_string=" -eddy_mask ${temp_mask} "

      eddy_opts='--repol --slm=linear'
      n_shells=$(mrinfo -shell_bvalues ${degibbs} | wc -w)
      [[ ${n_shells} -gt 2 ]] && eddy_opts="${eddy_opts} --data_is_shelled "

      # Build or select SE-EPI from reverse-PE
      se_epi=""; se_epi_nii="${work_dir}/${id}_rev_seepi.nii.gz"
      if [[ -n "${revpe:-}" && -f "${revpe}" ]]; then
        rev_base="${revpe%.gz}"; rev_base="${rev_base%.nii}"
        if [[ -f "${rev_base}.bval" ]]; then
          idx=$(awk '{for(i=1;i<=NF;i++) if ($i<50){print (i-1); exit}}' "${rev_base}.bval" || true)
          [[ -z "$idx" ]] && idx=0
          fslroi "${revpe}" "${se_epi_nii}" "$idx" 1
        else
          cp "${revpe}" "${se_epi_nii}"
        fi
        se_epi="${se_epi_nii}"
      fi
      # Fallback: if reverse is single-volume, use it directly
      if [[ -z "$se_epi" && -n "${revpe:-}" && -f "$revpe" ]]; then
        nvol=$(fslval "$revpe" dim4 2>/dev/null || echo 1)
        if [[ -z "$nvol" || "$nvol" -eq 1 ]]; then
          se_epi="$revpe"
          echo "[stage 04] Fallback: using reverse as SE-EPI -> $se_epi"
        fi
      fi

# === Build a 2-volume SE-EPI pair (main b0 + reverse b0) ===
se_epi="${work_dir}/${id}_rev_seepi_pair.nii.gz"

		# 1) main b0 (from your degibbs’d DWI)
		b0_main="${work_dir}/${id}_b0_main.nii.gz"
		if command -v dwiextract >/dev/null 2>&1; then
		  # robust: extract b=0 via MRtrix, then take first volume
		  dwiextract -bzero "${degibbs}" - | mrconvert - "${b0_main}" -strides +1,+2,+3,+4 -force
		  # ensure single volume
		  if [[ "$(fslval "${b0_main}" dim4)" -gt 1 ]]; then
			fslroi "${b0_main}" "${b0_main}" 0 1
		  fi
		else
		  # fallback: take first b0 index from the FSL bvals you already wrote
		  if [[ -s "${bvals}" ]]; then
			idx_b0=$(awk '{for(i=1;i<=NF;i++) if ($i<50){print i-1; exit}}' "${bvals}")
			[[ -z "${idx_b0}" ]] && idx_b0=0
		  else
			idx_b0=0
		  fi
		  fslroi "${raw_nii}" "${b0_main}" "${idx_b0}" 1
		fi
		
		# 2) reverse b0 (from your reverse-PE NIfTI)
		b0_rev="${work_dir}/${id}_b0_rev.nii.gz"
		if [[ -n "${revpe:-}" && -f "${revpe}" ]]; then
		  nrev=$(fslval "${revpe}" dim4 2>/dev/null || echo 1)
		  if [[ "${nrev}" -gt 1 ]]; then
			# take first volume (typically b0)
			fslroi "${revpe}" "${b0_rev}" 0 1
		  else
			cp -f "${revpe}" "${b0_rev}"
		  fi
		else
		  echo "[ERR] -rpe_pair requested but reverse-phase EPI not found"; exit 1
		fi
		
		# 3) merge into a 2-volume SE-EPI pair
		fslmerge -t "${se_epi}" "${b0_main}" "${b0_rev}"
		nev=$(fslval "${se_epi}" dim4 2>/dev/null || echo 0)
		if [[ "${nev}" -lt 2 || $((nev % 2)) -ne 0 ]]; then
		  echo "[ERR] se_epi must contain an even number of vols (got ${nev})"; exit 1
		fi
		echo "[stage 04] SE-EPI pair ready: ${se_epi} (vols=${nev})"

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
      fi
    else
      : # non-FSL branch omitted
    fi
  fi

  # 05. Bias field correction
  stage='05'
  debiased=${work_dir}/${id}_${stage}_dwi_nii4D_biascorrected.mif
  if [[ ! -f ${debiased} ]]; then
    dwibiascorrect ants ${preprocessed} ${debiased} -scratch ${work_dir}/
  fi
  if [[ ! -f ${debiased} ]]; then
    echo "Process died during stage ${stage}" && exit 1
  elif ((${cleanup})); then
    [[ -f ${preprocessed} ]] && rm ${preprocessed}
    [[ -f ${temp_mask} ]] && rm ${temp_mask}
  fi
else
  echo "Debiased mif file already exists; skipping to Stage ${pds_plus_one}."
fi

# 06. Extract b0 and shell-mean DWI
stage='06'
b0=${work_dir}/${id}_b0.nii.gz
dwi=${work_dir}/${id}_dwi.nii.gz
shells=$(mrinfo -shell_bvalues ${debiased})
shells=${shells%\ }
shellmeans=${work_dir}/${id}_shellmeans.mif
if [[ ! -f ${b0} || ! -f ${dwi} ]]; then
  if [[ ! -f ${shellmeans} ]]; then
    dwishellmath ${debiased} mean ${shellmeans}
  fi
  i=0
  for shelly_long in ${shells}; do
    if (( i )); then
      c_image="${work_dir}/${id}_dwi_b${shelly_long}.nii.gz"
    else
      c_image="${work_dir}/${id}_b0.nii.gz"
    fi
    if [[ ! -e ${c_image} ]]; then
      mrconvert ${shellmeans} -coord 3 ${i} -axes 0,1,2 ${c_image}
    fi
    let "i++"
  done

  dwi_stack_mif="${work_dir}/${id}_dwi_stack.mif"
  if [[ ! -f ${dwi} ]]; then 
    if [[ $i -eq 2 ]]; then
      mv ${c_image} ${dwi}
    else
      if [[ ! -f ${dwi_stack_mif} ]]; then
        s_idc=$(mrinfo -shell_indices ${debiased})
        s_idc=${s_idc#*\ }
        s_idc=${s_idc%\ }
        s_idc=${s_idc// /,}
        mrconvert ${debiased} ${dwi_stack_mif} -coord 3 ${s_idc}
      fi
      mrmath ${dwi_stack_mif} mean ${dwi} -axis 3
      if [[ ! -f ${dwi} ]]; then
        echo "Process died during stage ${stage}" && exit 1
      elif ((${cleanup})); then
        [[ -f ${dwi_stack_mif} ]] && rm ${dwi_stack_mif}
      fi
      if [[ ! -f ${b0} ]]; then
        echo "Process died during stage ${stage}" && exit 1
      elif ((${cleanup})); then
        [[ -f ${shellmeans} ]] && rm ${shellmeans}
      fi
    fi
  fi
fi
if [[ ! -f ${b0} || ! -f ${dwi} ]]; then
  echo "Process died during stage ${stage}" && exit 1
elif ((${cleanup})); then
  [[ -f ${shellmeans} ]] && rm ${shellmeans}
  [[ -f ${dwi_stack_mif} ]] && rm ${dwi_stack_mif}
fi

# 06.5 Make a brain mask from b0
mask=${work_dir}/${id}_mask.nii.gz
if [[ ! -f ${mask} ]]; then
  if [[ -f ${b0} ]]; then
    bet ${b0} ${mask%_mask.nii.gz} -m -n
    fslmaths ${mask} -add 0 ${mask} -odt char
  fi
fi
if [[ ! -f ${mask} ]]; then
  echo "Process died during stage 06.5" && exit 1
fi

# 07. Tensor fit
stage='07'
strides=${work_dir}/${id}_strides.txt
[[ -f $strides ]] || mrinfo -strides ${debiased} > $strides
dt=${work_dir}/${id}_${stage}_dt.mif
if [[ ! -f ${dt} || ! -f ${b0} ]]; then
  dwi2tensor ${debiased} ${dt} -mask ${mask}
fi
[[ -f ${dt} ]] || { echo "Process died during stage ${stage}" && exit 1; }

# 08. Metrics
stage='08'
fa=${work_dir}/${id}_${stage}_fa.mif
fa_nii=${work_dir}/${id}_fa.nii.gz
adc=${work_dir}/${id}_${stage}_adc.mif
adc_nii=${work_dir}/${id}_adc.nii.gz
rd=${work_dir}/${id}_${stage}_rd.mif
rd_nii=${work_dir}/${id}_rd.nii.gz
ad=${work_dir}/${id}_${stage}_ad.mif
ad_nii=${work_dir}/${id}_ad.nii.gz
out_string=" "
if [[ ! -f ${fa_nii} || ! -f ${adc_nii} || ! -f ${rd_nii} || ! -f ${ad_nii} ]]; then
  if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]]; then
    for contrast in fa adc rd ad; do
      c_mif=${work_dir}/${id}_${stage}_${contrast}.mif
      nii=${work_dir}/${id}_${contrast}.nii.gz
      if [[ ! -f ${nii} && ! -f ${c_mif} ]]; then
        out_string="${out_string} -${contrast} ${c_mif}"
      fi
    done
    tensor2metric ${dt} ${out_string}
  fi
  if [[ ! -f ${fa} || ! -f ${adc} || ! -f ${rd} || ! -f ${ad} ]]; then
    echo "Process died during stage ${stage}" && exit 1
  fi
fi

# 09. Convert metrics to NIfTI
for contrast in fa adc rd ad; do
  mif=${work_dir}/${id}_${stage}_${contrast}.mif
  nii=${work_dir}/${id}_${contrast}.nii.gz
  if [[ ! -f ${nii} ]]; then
    mrconvert ${mif} ${nii}
  fi
  if [[ -f ${nii} && -f ${mif} ]]; then
    if ((${cleanup})); then
      rm ${mif}
    fi
  fi
done

# 10. Response functions
stage='10'
wm_txt=${work_dir}/${id}_wm.txt
gm_txt=${work_dir}/${id}_gm.txt
csf_txt=${work_dir}/${id}_csf.txt
voxels_mif=${work_dir}/${id}_voxels.mif.gz
if [[ ! -f ${wm_txt} || ! -f ${gm_txt} || ! -f ${csf_txt} || ! -f ${voxels_mif} ]]; then
  dwi2response dhollander ${debiased} ${wm_txt} ${gm_txt} ${csf_txt} -voxels ${voxels_mif} -mask ${mask} -scratch ${work_dir}
fi
if [[ ! -f ${wm_txt} || ! -f ${gm_txt} || ! -f ${csf_txt} || ! -f ${voxels_mif} ]]; then
  echo "Process died during stage ${stage}" && exit 1
fi

# 11. FODs
stage='11'
wmfod_mif=${work_dir}/${id}_wmfod.mif.gz
gmfod_mif=${work_dir}/${id}_gmfod.mif.gz
csffod_mif=${work_dir}/${id}_csffod.mif.gz
if [[ ! -f ${wmfod_mif} ]]; then
  dwi2fod msmt_csd ${debiased} -mask ${mask} ${wm_txt} ${wmfod_mif}
fi
[[ -f ${wmfod_mif} ]] || { echo "Process died during stage ${stage}" && exit 1; }

# 12. mtnormalise
stage='12'
wmfod_norm_mif=${work_dir}/${id}_wmfod_norm.mif.gz
if [[ ! -f ${wmfod_norm_mif} ]]; then
  mtnormalise ${wmfod_mif} ${wmfod_norm_mif} -mask ${mask}
fi
[[ -f ${wmfod_norm_mif} ]] || { echo "Process died during stage ${stage}" && exit 1; }

# 13. tckgen
stage='13'
tracks_10M_tck=${work_dir}/${id}_tracks_10M.tck
smaller_tracks=${work_dir}/${id}_smaller_tracks_2M.tck
if [[ ! -f ${smaller_tracks} ]]; then
  if [[ ! -f ${tracks_10M_tck} ]]; then
    tckgen -backtrack -seed_image ${mask} -maxlength 1000 -cutoff 0.1 -select 10000000 ${wmfod_norm_mif} ${tracks_10M_tck} -nthreads 10
  fi
  [[ -f ${tracks_10M_tck} ]] || { echo "Process died during stage ${stage}" && exit 1; }
  # 14. tckedit down to 2M
  stage='14'
  tckedit ${tracks_10M_tck} -number 2000000 -minlength 0.1 ${smaller_tracks}
fi
if [[ ! -f ${smaller_tracks} ]]; then
  echo "Process died during stage ${stage}" && exit 1
elif ((${cleanup})); then
  [[ -f ${tracks_10M_tck}  ]] && rm ${tracks_10M_tck}
fi

# 14.5 QA tracks
stage=14.5
QA_tracks=${work_dir}/${id}_QA_tracks_50k.tck
if [[ ! -f ${QA_tracks} ]]; then
  tckedit ${smaller_tracks} ${QA_tracks} -number 50000 -nthreads 10
fi
if [[ ! -f ${QA_tracks} ]]; then
  echo "NON-CRITICAL FAILURE: no QA_tracks were produced during stage ${stage}."
  echo "   Missing file: ${QA_tracks}."
fi

# 15. tcksift2
stage='15'
sift_mu_txt=${work_dir}/${id}_sift_mu.txt
sift_coeffs_txt=${work_dir}/${id}_sift_coeffs.txt
sift_1M_txt=${work_dir}/${id}_sift_1M.txt
if [[ ! -f  ${sift_mu_txt} || ! -f ${sift_coeffs_txt} || ! -f ${sift_1M_txt} ]]; then
  tcksift2 -out_mu ${sift_mu_txt} -out_coeffs ${sift_coeffs_txt} ${smaller_tracks} ${wmfod_norm_mif} ${sift_1M_txt}
fi
if [[ ! -f  ${sift_mu_txt} || ! -f ${sift_coeffs_txt} || ! -f ${sift_1M_txt} ]]; then
  echo "Process died during stage ${stage}" && exit 1
fi

# 16. Labels backport
stage='16'
labels=${work_dir}/${id}_IITmean_RPI_labels.nii.gz
if [[ ! -e ${labels} ]]; then
  source_labels=${BIGGUS_DISKUS}/../mouse/VBM_25${project}01_IITmean_RPI-results/connectomics/${id}/${id}_IITmean_RPI_labels.nii.gz
  if [[ -e ${source_labels} ]]; then
    cp ${source_labels} ${labels}
  fi
  if [[ ! -e ${labels} ]]; then
    echo "Process stopped at ${stage}."
    echo "SAMBA labels do not exist yet."
    echo "Please run samba-pipe and backport the labels to this folder." && exit 0
  fi
fi

parcels_mif=${work_dir}/${id}_IITmean_RPI_parcels.mif.gz
if [[ ! -f ${parcels_mif} ]]; then
  mrconvert ${labels} ${parcels_mif}
fi

max_label=$(mrstats -output max ${parcels_mif} | cut -d ' ' -f1)
if [[ $max_label -gt 84 ]]; then
  index2=(8 10 11 12 13 17 18 26 47 49 50 51 52 53 54 58 1001 1002 1003 1005 1006 1007 1008 1009 1010 1011 1012 1013 1014 1015 1016 1017 1018 1019 1020 1021 1022 1023 1024 1025 1026 1027 1028 1029 1030 1031 1032 1033 1034 1035 2001 2002 2003 2005 2006 2007 2008 2009 2010 2011 2012 2013 2014 2015 2016 2017 2018 2019 2020 2021 2022 2023 2024 2025 2026 2027 2028 2029 2030 2031 2032 2033 2034 2035)
  decomp_parcels=${parcels_mif%\.gz}
  if [[ ! -f ${decomp_parcels} ]]; then
    gunzip ${parcels_mif}
  fi 
  for i in $(seq 1 84); do
    mrcalc ${decomp_parcels} ${index2[$i-1]} $i -replace ${decomp_parcels} -force
  done
  [[ -f ${parcels_mif} ]] && rm ${parcels_mif}
  gzip ${decomp_parcels}
fi

max_label=$(mrstats -output max ${parcels_mif} | cut -d ' ' -f1)
if [[ ${max_label} -gt 84 ]]; then
  echo "Process died during stage 16b" && exit 1
fi

# 17. Connectomes
stage='17'
conn_folder=/mnt/newStor/paros//paros_WORK/${project}_connectomics/${id}_connectomics
if ((! $use_fsl)); then
  conn_folder=/mnt/newStor/paros//paros_WORK/${project}_connectomics/${id}_with_coreg_connectomics
fi
[[ -d ${conn_folder} ]] || mkdir ${conn_folder}

distances_csv=${conn_folder}/${id}_distances.csv
if [[ ! -f ${distances_csv} ]]; then
  echo "File not found: ${distances_csv}; Running tck2connectome..."
  tck2connectome ${smaller_tracks} ${parcels_mif} ${distances_csv} -zero_diagonal -symmetric -scale_length -stat_edge mean
fi

mean_FA_per_streamline=${conn_folder}/${id}_per_strmline_mean_FA.csv
if [[ ! -f ${mean_FA_per_streamline} ]]; then
  tcksample ${smaller_tracks} ${fa_nii} ${mean_FA_per_streamline} -stat_tck mean
fi

mean_FA_connectome=${conn_folder}/${id}_mean_FA_connectome.csv
if [[ ! -f ${mean_FA_connectome} ]]; then
  echo "File not found: ${mean_FA_connectome}; Running tck2connectome..."
  tck2connectome ${smaller_tracks} ${parcels_mif} ${mean_FA_connectome} -zero_diagonal -symmetric -scale_file ${mean_FA_per_streamline} -stat_edge mean
fi

# 18. (Other connectome variants)
stage='18'
parcels_csv_2=${conn_folder}/${id}_con_plain.csv
assignments_parcels_csv2=${conn_folder}/${id}_assignments_con_plain.csv
if [[ ! -f ${parcels_csv_2} || ! -f ${assignments_parcels_csv2} ]]; then
  echo "File not found: ${parcels_csv_2}; Running tck2connectome..."
  tck2connectome -symmetric -zero_diagonal ${smaller_tracks} ${parcels_mif} ${parcels_csv_2} -out_assignment ${assignments_parcels_csv2} -force
fi

parcels_csv_3=${conn_folder}/${id}_con_sift.csv
assignments_parcels_csv3=${conn_folder}/${id}_assignments_con_sift.csv
if [[ ! -f ${parcels_csv_3} || ! -f ${assignments_parcels_csv3} ]]; then
  echo "File not found: ${parcels_csv_3}; Running tck2connectome..."
  tck2connectome -symmetric -zero_diagonal -tck_weights_in ${sift_1M_txt} ${smaller_tracks} ${parcels_mif} ${parcels_csv_3} -out_assignment ${assignments_parcels_csv3} -force
fi

echo "The ${proc_name}_${id} pipeline has completed! Thanks for patronizing this wonderful script!" && exit 0
