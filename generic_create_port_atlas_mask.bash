#!/bin/bash
#SBATCH -p normal
#SBATCH  --mem=60000 
#SBATCH  --hint=multithread 
#SBATCH  -v
#SBATCH  -s 
#SBATCH  --output=/mnt/newStor/paros/paros_WORK/mouse/VBM_26glp01_invivoAPOE1-work/preprocess/masks//sbatch//slurm-%j.out 
#$ -l h_vmem=60000M,vf=60000M 
#$ -N generic_create_port_atlas_mask 
#$ --mail-user=floydmitchell@hotmail.com 
#$ --mail-type=END,FAIL 
#$ -o /mnt/newStor/paros/paros_WORK/mouse/VBM_26glp01_invivoAPOE1-work/preprocess/masks//sbatch//slurm-$JOB_ID.out 
#$ -e /mnt/newStor/paros/paros_WORK/mouse/VBM_26glp01_invivoAPOE1-work/preprocess/masks//sbatch//slurm-$JOB_ID.out 
bad_mask=$1;
echo "bad_mask = ${bad_mask}"
good_mask=$2;
echo "good_mask = ${good_mask}"
rigid_only=0;
if [[ $3 ]];then
	rigid_only=1;
fi
echo "Rigid only = ${rigid_only}-------------------"
good_id=${good_mask##*/};
good_id=${good_id%_mask.nii.gz};
good_id=${good_id%mask.nii.gz};
echo "good_id = ${good_id}"
norm_mask=${bad_mask%_mask.nii.gz}_norm_mask.nii.gz;
echo "norm_mask = ${norm_mask}"
prefix=${bad_mask/.nii.gz/_and_${good_id}_};
echo "prefix = ${prefix}"
atlas_mask=${bad_mask%_mask.nii.gz}_${good_id}_mask.nii.gz
echo "atlas_mask = ${atlas_mask}"
#port_mask=${bad_mask%_mask.nii.gz}_port_mask.nii.gz;
#echo "port_mask = ${port_mask}";
port_mask_cp=${bad_mask%_mask.nii.gz}_port_${good_id}_mask.nii.gz;
echo "port_mask_cp = ${port_mask_cp}"
echo "Let\'s get this party started!";
echo "Step 1";
ImageMath 3 ${norm_mask} Normalize ${bad_mask};
echo "Step 2"
if [[ $rigid_only ]];then
	cmd="antsRegistration -v 1 -d 3 -r [${good_mask},${norm_mask},1]  -m MeanSquares[${good_mask},${norm_mask},1,32,random,0.3] -t rigid[0.1] -c [3000x3000x0x0,1.e-8,20]  -s 4x2x1x0.5vox -f 6x4x2x1 -u 1 -z 1 -o ${prefix}";
else
        cmd="antsRegistration -v 1 -d 3 -r [${good_mask},${norm_mask},1]  -m MeanSquares[${good_mask},${norm_mask},1,32,random,0.3] -t affine[0.1] -c [3000x3000x0x0,1.e-8,20]  -s 4x2x1x0.5vox -f 6x4x2x1 -u 1 -z 1 -o ${prefix}";
fi
$cmd;
echo "Step 3"
echo "Step 4"
antsApplyTransforms -v 1 --float -d 3 -i ${good_mask} -o ${atlas_mask} -t [${prefix}0GenericAffine.mat, 1] -r ${norm_mask} -n NearestNeighbor;
echo "Step 5"
iMath 3 ${atlas_mask} MD ${atlas_mask} 2 1 ball 1;
echo "Step 6"
SmoothImage 3 ${atlas_mask} 1 ${atlas_mask} 0 1;
echo "Step 7"
iMath 3 ${atlas_mask} ME ${atlas_mask} 2 1 ball 1;
ImageMath 3 ${port_mask_cp} Normalize ${atlas_mask};
#echo "Step 8"
echo "All done turning ${bad_mask} into ${port_mask_cp}!" 
