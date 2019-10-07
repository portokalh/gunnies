shebang='#!/bin/bash';
clus_batch_directory='/Users/alex/brain_data/19abb14/mybatches/';

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

end

% sbatch_cmd = ['sbatch --mem=' ?memory_request_in_MB?'?-s -p defq --out=' sbatch_directory '/slurm-%j.out ' mubatch_file]
% [res,msg]=system(sbatch_cmd);
%bash sbatchgroup.bash