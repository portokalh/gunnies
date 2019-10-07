shebang='#!/bin/bash';




clus_batch_directory='/Users/alex/brain_data/19abb14/mybatches/';

mysbatch_file=[clus_batch_directory 'sbatchgroup.bash'];
sfid=fopen(mysbatch_file, 'w');
fprintf(sfid,'%s\n' ,shebang)

%sfid=fopen(mysbatch_file, 'w');
%fprintf(sfid,'%s\n' ,shebang)

runno={'N57446' , 'N57498', 'N57500', 'N57502', 'N57504'};

for ii=1:numel(runno)
    myname= char(runno(ii))

mysbatch_file=[clus_batch_directory char(runno(ii)) '_sync.bash'];
fid=fopen(mysbatch_file, 'w');
fprintf(fid,'%s\n' ,shebang)
   
cmd1=['rsync -rpv /Volumes/delosspace-1/diffusionN57446dsi_studio-results/nii4D_' char(runno(ii)) '.nii  /Volumes/dusom_abadea_nas1/19abb14'];
cmd2=['rsync -rpv /Volumes/delosspace-1/' char(runno(ii)) '*  /Volumes/dusom_abadea_nas1/19abb14'];
cmd3=['rsync -rpv /Volumes/delosspace-1/' char(runno(ii)) '.work /Volumes/dusom_abadea_nas1/19abb14'];
cmd4=['rsync -rpv /Volumes/dusom_abadea_nas1/19abb14/Volumes/delosspace-1/co_reg_' char(runno(ii)) '_m00-work /Volumes/dusom_abadea_nas1/19abb14'];

fprintf(fid, '%s;\n',cmd1);
fprintf(fid, '%s;\n',cmd2);
fprintf(fid, '%s;\n',cmd3);
fprintf(fid, '%s;\n',cmd4);

fclose(fid)


%sbatch_cmd = ['sbatch --mem=' mem_request_MB  ' -cpu 4 -s -p defq --out=' clus_batch_directory '/slurm' num2str(ii) '.out ' my_clus_batch_file]
sbatch_cmd=['bash ' mysbatch_file]

fprintf(sfid, '%s;\n',sbatch_cmd);

end

fclose(sfid)


% sbatch_cmd = ['sbatch --mem=' ?memory_request_in_MB?'?-s -p defq --out=' sbatch_directory '/slurm-%j.out ' mubatch_file]
% [res,msg]=system(sbatch_cmd);
%bash sbatchgroup.bash