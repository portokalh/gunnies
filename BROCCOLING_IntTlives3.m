%my4dnii='/Users/alex/brain_data/motor/25october2016/4dnii_s1/fa4d.nii.gz'; %myjacs4d_2MDT.nii.gz'
PREFIX='IntTlivejac'; %JACFIX
my4dnii=['/Users/alex/brain_data/motor/25october2016/4dnii_s1/' PREFIX '4d.nii.gz'];

myshell_file=['/Users/alex/Documents/MATLAB/alex/motor/broccoli_' PREFIX '_e3mask.sh']
%myshell_file=['/Users/alex/Documents/MATLAB/alex/motor/broccoli_' PREFIX '_gmmask.sh']

shebang='#!/bin/bash';
cmd1=['/Users/alex/BROCCOLI-master/compiled/Bash/Mac/Release/RandomiseGroupLevel ' my4dnii ' -design bjac.mat -contrasts bjac.con -permutations 5000 -cdt 1.71 -inferencemode 2 -platform 0 -device 1 -mask MDT_mask_wm.nii.gz -output ' PREFIX 'corr' ' -writepermutations myperms'] 
cmd1=['/Users/alex/BROCCOLI-master/compiled/Bash/Mac/Release/RandomiseGroupLevel ' my4dnii ' -design bjac.mat -contrasts bjac.con -permutations 5000 -cdt 1.71 -inferencemode 2 -platform 0 -device 1 -mask MDT_mask_e3.nii.gz -output ' PREFIX 'corr' ' -writepermutations myperms'] 
%cmd1=['/Users/alex/BROCCOLI-master/compiled/Bash/Mac/Release/RandomiseGroupLevel ' my4dnii ' -design bjac.mat -contrasts bjac.con -permutations 5000 -cdt 1.71 -inferencemode 2 -platform 0 -device 1 -mask MDT_mask_gm.nii.gz -output ' PREFIX 'corr' ' -writepermutations myperms'] 

cmd2=['fslsplit ' PREFIX 'corr_perm_tvalues.nii ' PREFIX 'corr_perm_tsplit -t']
cmd3=['fslsplit ' PREFIX 'corr_perm_pvalues.nii ' PREFIX 'corr_perm_psplit -t']


cmd4=['fslmaths ' PREFIX 'corr_perm_psplit0000.nii.gz -thr 0.95 -bin tmpthresh.nii.gz']
cmd5=['fslmaths tmpthresh.nii.gz -mul ' PREFIX 'corr_perm_tsplit0000.nii.gz ' PREFIX 'corr_perm_tvalues1thresh0p95.nii.gz']

cmd6=['fslmaths ' PREFIX 'corr_perm_psplit0001.nii.gz -thr 0.95 -bin tmpthresh.nii.gz']
cmd7=['fslmaths tmpthresh.nii.gz -mul ' PREFIX 'corr_perm_tsplit0001.nii.gz ' PREFIX 'corr_perm_tvalues2thresh0p95.nii.gz']
 

sfid=fopen(myshell_file, 'w');
cmd0=['export PATH=$PATH://Users/alex/BROCCOLI-master/compiled/Bash/Mac/Release'] 
cmd00=['export BROCCOLI_DIR=/Users/alex/BROCCOLI-master/']
fprintf(sfid,'%s\n' ,shebang)
fprintf(sfid, '%s;\n',cmd0);
fprintf(sfid, '%s;\n',cmd00);
fprintf(sfid, '%s;\n',cmd1);
fprintf(sfid, '%s;\n',cmd2);
fprintf(sfid, '%s;\n',cmd3);
fprintf(sfid, '%s;\n',cmd4);
fprintf(sfid, '%s;\n',cmd5);
fprintf(sfid, '%s;\n',cmd6);
fprintf(sfid, '%s;\n',cmd7);
fclose(sfid)