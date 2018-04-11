%start take this bit and make it a function to plot ROIs
%28 rank for 3 vs 4 groups is hippocampus roi 51
for i=1:nv
    indroi=myvertices(i)
myHc1_degreew=mydeg(indroi, ind1)'
myHc2_degreew=mydeg(indroi, ind2)'
% myHc3_degreew=mydeg(indroi, ind3)'
% myHc4_degreew=mydeg(indroi, ind4)'

h = {myHc1_degreew; myHc2_degreew}
%h = {myHc1_degreew; myHc2_degreew;myHc3_degreew;myHc4_degreew}
hf = figure('Name',char(mynames(indroi)))

cmap=[0 1 0; 0 0 1 ; 1 1 1; 1 0 0]
aboxplot(h, 'labels', mynames(indroi), 'colormap', cmap,'WidthE', .4, 'WidthL', .8, 'WidthS', 1, 'outliermarkersize', 5); % Add a legend); % Advanced box plot

legend('Control', 'Reacher')
%legend('$\sigma=2$','$\sigma=4$')


ylabel('Volume(#)', 'FontSize', 16, 'FontWeight', 'bold');

set(gca,'FontSize',16,'FontName','FixedWidth', 'FontWeight', 'bold');
%xticklabel_rotate([],90);
fname=char([pathfigs 'Volume' char(mynames(indroi)) '.png'])

saveas(hf, fname,'png');
export_fig(fname, '-png', '-r200');
end
%end take this bit and make it a function to plot ROIs